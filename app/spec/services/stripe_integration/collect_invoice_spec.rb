require 'rails_helper'

RSpec.describe StripeIntegration::CollectInvoice do
  let(:gateway) { FakeStripeGateway.new }
  let(:invoice) do
    subscription = create_subscription
    create_usage(subscription: subscription)
    generate_invoice(subscription: subscription).record
  end
  let(:collection) { StripeIntegration::RequestCollection.call(invoice: invoice) }

  before { configure_stripe_test }

  it 'persists one collection intent and hands one controlled invoice to Stripe' do
    request = collection
    expect(StripeIntegration::RequestCollection.call(invoice: invoice).id).to eq(request.id)
    described_class.new(collection: request, gateway: gateway).call
    described_class.new(collection: request.reload, gateway: gateway).call
    expect([gateway.create_count('customer'), gateway.create_count('invoice'),
            gateway.create_count('item')]).to eq([1, 1, 1])
    expect(gateway.calls.count { |call| call[:action] == :finalize }).to eq(1)
    expect([request.reload.status, StripeOperation.count, OutboxRecord.count]).to eq(['succeeded', 4, 1])
    expect(invoice.reload.stripe_invoice_id).to be_present
  end

  %w[customer invoice item].each do |kind|
    it "recovers a lost #{kind} creation response without another POST" do
      gateway.fail_after_create = kind
      worker = described_class.new(collection: collection, gateway: gateway)
      expect { worker.call }.to raise_error(StripeIntegration::Retryable)
      expect(collection.reload.status).to eq('pending')
      worker.call
      expect(gateway.create_count(kind)).to eq(1)
      expect(collection.reload.status).to eq('succeeded')
    end
  end

  it 'recovers a lost finalization response by reading the same invoice' do
    gateway.fail_after_finalize = true
    worker = described_class.new(collection: collection, gateway: gateway)
    expect { worker.call }.to raise_error(StripeIntegration::Retryable)
    worker.call
    expect(gateway.calls.count { |call| call[:action] == :finalize }).to eq(1)
    expect(collection.reload.status).to eq('succeeded')
  end

  it 'stops rather than recreating an unknown operation after its safe replay window' do
    operations = StripeIntegration::Operations.new(gateway: gateway)
    operation = operations.prepare(key: "customer:#{invoice.customer_id}", kind: 'customer', customer: invoice.customer)
    operation.update!(first_attempted_at: 24.hours.ago)
    worker = described_class.new(collection: collection, gateway: gateway)
    expect { worker.call }.to raise_error(StripeIntegration::ReviewRequired, 'idempotency_window_expired')
    expect(gateway.create_count('customer')).to eq(0)
    expect(collection.reload.status).to eq('review')
    expect(operation.reload.first_attempted_at).to be < 23.hours.ago
  end

  it 'does not reset the original operation window during manual replay' do
    operations = StripeIntegration::Operations.new(gateway: gateway)
    operation = operations.prepare(key: "customer:#{invoice.customer_id}", kind: 'customer', customer: invoice.customer)
    operation.update!(first_attempted_at: 24.hours.ago)
    worker = described_class.new(collection: collection, gateway: gateway)
    expect { worker.call }.to raise_error(StripeIntegration::ReviewRequired)
    StripeIntegration::RecoverySweep.replay(collection.reload)
    expect { worker.call }.to raise_error(StripeIntegration::ReviewRequired, 'idempotency_window_expired')
    expect(gateway.create_count('customer')).to eq(0)
  end

  it 'cannot mutate a persisted request payload or first-attempt timestamp' do
    operations = StripeIntegration::Operations.new(gateway: gateway)
    operation = operations.prepare(key: "customer:#{invoice.customer_id}", kind: 'customer', customer: invoice.customer)
    operation.update!(first_attempted_at: Time.current)
    expect { operation.update!(first_attempted_at: nil) }.to raise_error(ActiveRecord::RecordInvalid)
    expect { operation.update!(payload: { changed: true }) }.to raise_error(ActiveRecord::ActiveRecordError)
  end

  it 'keeps pending invoice items out of the controlled invoice' do
    described_class.new(collection: collection, gateway: gateway).call
    payload = gateway.calls.find { |call| call[:action] == :create && call[:kind] == 'invoice' }.fetch(:payload)
    expect(payload).to include('auto_advance' => false, 'pending_invoice_items_behavior' => 'exclude',
                               'collection_method' => 'charge_automatically')
    expect(gateway.calls.find { |call| call[:kind] == 'item' && call[:action] == :create }.dig(:payload, 'invoice'))
      .to eq(invoice.reload.stripe_invoice_id)
  end

  it 'rejects amounts outside the deliberate application collection range' do
    subscription = create_subscription(plan: create_plan(unit_amount: 1))
    create_usage(subscription: subscription, quantity: 1)
    small = generate_invoice(subscription: subscription).record
    expect { StripeIntegration::RequestCollection.call(invoice: small) }
      .to raise_error(Billing::Error) { |error| expect(error.code).to eq('unsupported_collection_amount') }
    expect(InvoiceCollection.count).to eq(0)
  end
end
