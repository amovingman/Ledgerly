require 'rails_helper'
require 'concurrent'

RSpec.describe StripeIntegration::ProcessEvent, :concurrency do
  self.use_transactional_tests = false

  before { configure_stripe_test }

  around do |example|
    clean_billing_data
    example.run
  ensure
    clean_billing_data
  end

  def parallel_calls(count = 4, &)
    barrier = Concurrent::CyclicBarrier.new(count)
    threads = Array.new(count) { Thread.new { worker_call(barrier, &) } }
    threads.map(&:value)
  ensure
    threads&.each(&:join)
  end

  def worker_call(barrier)
    ActiveRecord::Base.connection_pool.with_connection do
      raise 'Barrier timed out' unless barrier.wait(10)

      yield
    end
  end

  def check_network_boundary(gateway)
    allow(gateway).to receive(:create).and_wrap_original do |method, operation|
      raise 'Network work inside a transaction' if ActiveRecord::Base.connection.transaction_open?

      method.call(operation)
    end
  end

  def queued_collection
    subscription = create_subscription
    create_usage(subscription: subscription)
    invoice = generate_invoice(subscription: subscription).record
    StripeIntegration::RequestCollection.call(invoice: invoice)
  end

  it 'stores one receipt and one outbox record under concurrent webhook deliveries' do
    raw = JSON.generate(stripe_payload(type: 'customer.updated'))
    signature = sign_stripe(raw)
    results = parallel_calls { StripeIntegration::ReceiveEvent.call(raw: raw, signature: signature) }
    expect(results.map { |result| result.record.id }.uniq.size).to eq(1)
    expect(results.count(&:replayed)).to eq(3)
    expect([StripeEvent.count, OutboxRecord.count]).to eq([1, 1])
  end

  it 'applies one payment and each partial refund once across distinct concurrent events' do
    invoice, gateway = paid_stripe_invoice(refunds: [20, 50])
    events = Array.new(4) { receive_stripe(stripe_payload(object_id: invoice.stripe_invoice_id)) }
    pending = Queue.new
    events.each { |event| pending << event.id }
    parallel_calls { process_stripe(StripeEvent.find(pending.pop), gateway) }
    expect([StripePayment.count, StripeRefund.count, LedgerTransaction.count, LedgerEntry.count]).to eq([1, 2, 4, 8])
    expect(events.map { |event| event.reload.status }).to all(eq('processed'))
    expect(invoice.reload.status).to eq('refunded')
    expect(LedgerEntry.sum(:debit)).to eq(LedgerEntry.sum(:credit))
  end

  it 'makes one remote collection and performs network work outside database transactions' do
    collection = queued_collection
    gateway = FakeStripeGateway.new
    check_network_boundary(gateway)
    parallel_calls do
      StripeIntegration::CollectInvoice.new(collection: InvoiceCollection.find(collection.id), gateway: gateway).call
    rescue StripeIntegration::Retryable => e
      raise unless e.code == 'operation_busy'
    end
    expect([gateway.create_count('customer'), gateway.create_count('invoice'),
            gateway.create_count('item')]).to eq([1, 1, 1])
    expect(collection.reload.status).to eq('succeeded')
  end
end
