require 'rails_helper'

RSpec.describe 'Versioned invoice reads', :concurrency do
  self.use_transactional_tests = false

  around do |example|
    clean_billing_data
    example.run
  ensure
    clean_billing_data
  end

  before do
    configure_stripe_test
    authenticate_api
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('READ_CACHE_ENABLED', '1').and_return('1')
    Billing::ReadCache.instance_variable_set(:@retry_after, nil)
  end

  def read_invoice(invoice)
    get "/api/v1/customers/#{invoice.customer_id}/invoices", params: { per_page: 100 },
                                                             headers: { 'Authorization' => 'Bearer request-test-key' }
    expect(response).to have_http_status(:ok)
    response.parsed_body.fetch('data').first
  end

  it 'refreshes cached headers after payment/refund reconciliation and keeps equivalent cached responses' do
    invoice, gateway = paid_stripe_invoice(refunds: [20, 50])
    initial = read_invoice(invoice)
    expect(read_invoice(invoice)).to eq(initial)
    event = receive_stripe(stripe_payload(type: 'charge.refunded', object_id: "ch_#{invoice.id}"))
    process_stripe(event, gateway)
    expect(read_invoice(invoice).fetch('status')).to eq('refunded')
    expect(Billing::CustomerBalance.call(customer: invoice.customer)).to eq([{ currency: 'USD', amount: 0 }])
  end

  it 'refreshes a cached header when a payment failure changes state without posting money' do
    invoice, gateway = paid_stripe_invoice
    expect(read_invoice(invoice).fetch('status')).to eq('issued')
    gateway.objects['invoice'][invoice.stripe_invoice_id].merge!('status' => 'open', 'amount_paid' => 0)
    gateway.objects['invoice_payment'].clear
    process_stripe(
      receive_stripe(stripe_payload(type: 'invoice.payment_failed', object_id: invoice.stripe_invoice_id)), gateway
    )
    expect(read_invoice(invoice).fetch('status')).to eq('payment_failed')
  end
end
