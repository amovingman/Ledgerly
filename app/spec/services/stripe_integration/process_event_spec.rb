require 'rails_helper'

RSpec.describe StripeIntegration::ProcessEvent do
  before { configure_stripe_test }

  it 'records a payment once across duplicate deliveries and distinct event IDs' do
    invoice, gateway = paid_stripe_invoice
    event = receive_stripe(stripe_payload(object_id: invoice.stripe_invoice_id))
    3.times { process_stripe(event, gateway) }
    another = receive_stripe(stripe_payload(object_id: invoice.stripe_invoice_id))
    process_stripe(another, gateway)
    expect([StripePayment.count, invoice.ledger_transactions.where(journal_type: 'payment').count]).to eq([1, 1])
    expect([event.reload.status, another.reload.status, invoice.reload.status]).to eq(%w[processed processed paid])
    expect(Billing::CustomerBalance.call(customer: invoice.customer)).to eq([{ currency: 'USD', amount: 0 }])
  end

  it 'processes a refund before payment/failure notifications and never regresses a settled invoice' do
    invoice, gateway = paid_stripe_invoice(refunds: [20, 50])
    refunded = receive_stripe(stripe_payload(type: 'charge.refunded', object_id: "ch_#{invoice.id}"))
    paid = receive_stripe(stripe_payload(object_id: invoice.stripe_invoice_id))
    failed = receive_stripe(stripe_payload(type: 'invoice.payment_failed', object_id: invoice.stripe_invoice_id))
    [refunded, paid, failed, refunded].each { |event| process_stripe(event, gateway) }
    expect([StripePayment.count, StripeRefund.count, LedgerTransaction.count, LedgerEntry.count]).to eq([1, 2, 4, 8])
    expect(invoice.reload.status).to eq('refunded')
    expect(LedgerEntry.sum(:debit)).to eq(LedgerEntry.sum(:credit))
    expect(Billing::CustomerBalance.call(customer: invoice.customer)).to eq([{ currency: 'USD', amount: 0 }])
  end

  it 'recognizes partial refunds without duplicating previous refunds' do
    invoice, gateway = paid_stripe_invoice(refunds: [20])
    first = receive_stripe(stripe_payload(type: 'charge.refunded', object_id: "ch_#{invoice.id}"))
    process_stripe(first, gateway)
    second = receive_stripe(stripe_payload(type: 'charge.refunded', object_id: "ch_#{invoice.id}"))
    process_stripe(second, gateway)
    expect([StripeRefund.count, StripeRefund.sum(:amount), invoice.reload.status]).to eq([1, 20, 'paid'])
  end

  it 'keeps a refund notification retryable until its canonical refund settles' do
    invoice, gateway = paid_stripe_invoice(refunds: [20])
    refund = gateway.objects['refund'].values.first
    refund['status'] = 'pending'
    event = receive_stripe(stripe_payload(type: 'charge.refunded', object_id: "ch_#{invoice.id}"))
    expect { process_stripe(event, gateway) }.to raise_error(StripeIntegration::Retryable, 'refund_pending')
    expect([event.reload.status, StripeRefund.count]).to eq(['received', 0])
    refund['status'] = 'succeeded'
    process_stripe(event, gateway)
    expect([event.reload.status, StripeRefund.sum(:amount)]).to eq(['processed', 20])
  end

  it 'rejects cumulative over-refunds before persisting any payment/refund effect' do
    invoice, gateway = paid_stripe_invoice(refunds: [40, 40])
    event = receive_stripe(stripe_payload(type: 'charge.refunded', object_id: "ch_#{invoice.id}"))
    expect { process_stripe(event, gateway) }.to raise_error(StripeIntegration::ReviewRequired)
    expect([StripePayment.count, StripeRefund.count, LedgerTransaction.count]).to eq([0, 0, 1])
    expect(event.reload.status).to eq('review')
  end

  it 'rolls back all financial effects if marking the event processed fails' do
    invoice, gateway = paid_stripe_invoice(refunds: [20])
    event = receive_stripe(stripe_payload(object_id: invoice.stripe_invoice_id))
    allow(event).to receive(:update!).and_wrap_original do |method, **attributes|
      raise StripeIntegration::Retryable, 'commit_interrupted' if attributes[:status] == 'processed'

      method.call(**attributes)
    end
    expect { process_stripe(event, gateway) }.to raise_error(StripeIntegration::Retryable)
    expect([StripePayment.count, StripeRefund.count, LedgerTransaction.count]).to eq([0, 0, 1])
    expect(invoice.reload.status).to eq('issued')
    expect(event.reload.status).to eq('received')
  end

  it 'ignores unsupported event types without constructing an API client' do
    event = receive_stripe(stripe_payload(type: 'customer.updated', object_id: 'cus_other'))
    allow(StripeIntegration::Gateway).to receive(:new).and_raise('unexpected client')
    described_class.new(event: event).call
    expect(event.reload.status).to eq('ignored')
  end

  it 'leaves unknown mappings recoverable and supports an operation-backed mapping race' do
    invoice, gateway = paid_stripe_invoice
    remote_id = invoice.stripe_invoice_id
    invoice.update!(stripe_invoice_id: nil)
    event = receive_stripe(stripe_payload(object_id: remote_id))
    expect { process_stripe(event, gateway) }.to raise_error(StripeIntegration::Retryable, 'unmapped_invoice')
    operation = StripeIntegration::Operations.new(gateway: gateway).prepare(
      key: "invoice:#{invoice.id}", kind: 'invoice', customer: invoice.customer, invoice: invoice
    )
    gateway.objects['invoice'][remote_id]['metadata'] = {
      'ledgerly_invoice_id' => invoice.id.to_s, 'ledgerly_operation' => operation.idempotency_key
    }
    process_stripe(event, gateway)
    expect(invoice.reload.stripe_invoice_id).to eq(remote_id)
    expect(event.reload.status).to eq('processed')
  end

  it 'sends a failed unpaid invoice to payment_failed without fabricating a payment' do
    invoice, gateway = paid_stripe_invoice
    gateway.objects['invoice'][invoice.stripe_invoice_id].merge!('status' => 'open', 'amount_paid' => 0)
    gateway.objects['invoice_payment'].clear
    event = receive_stripe(stripe_payload(type: 'invoice.payment_failed', object_id: invoice.stripe_invoice_id))
    process_stripe(event, gateway)
    expect(invoice.reload.status).to eq('payment_failed')
    expect([StripePayment.count, LedgerTransaction.count]).to eq([0, 1])
  end

  it 'rejects a live or mismatched canonical resource even when the event says test mode' do
    invoice, gateway = paid_stripe_invoice
    gateway.objects['invoice'][invoice.stripe_invoice_id]['livemode'] = true
    event = receive_stripe(stripe_payload(object_id: invoice.stripe_invoice_id))
    expect do
      process_stripe(event, gateway)
    end.to raise_error(StripeIntegration::ReviewRequired, 'remote_invoice_mismatch')
    expect(StripePayment.count).to eq(0)
  end

  it 'caps cumulative refunds against previously posted effects even if a provider snapshot is incomplete' do
    invoice, gateway = paid_stripe_invoice(refunds: [20])
    process_stripe(receive_stripe(stripe_payload(object_id: invoice.stripe_invoice_id)), gateway)
    gateway.objects['refund'].clear
    gateway.objects['refund']['re_new'] = { 'id' => 're_new', 'charge' => "ch_#{invoice.id}",
                                            'amount' => 60, 'currency' => 'usd', 'status' => 'succeeded' }
    event = receive_stripe(stripe_payload(type: 'charge.refunded', object_id: "ch_#{invoice.id}"))
    expect do
      process_stripe(event, gateway)
    end.to raise_error(StripeIntegration::ReviewRequired, 'refund_exceeds_payment')
    expect(StripeRefund.sum(:amount)).to eq(20)
    expect(invoice.reload.status).to eq('paid')
  end
end
