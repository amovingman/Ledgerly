require 'rails_helper'

RSpec.describe StripeIntegration::Gateway do
  before { configure_stripe_test }

  it 'reuses the SDK client across jobs on one thread instead of accumulating transport pools' do
    Thread.current[:ledgerly_stripe_client] = nil
    allow(Stripe::StripeClient).to receive(:new).and_call_original
    stub_request(:get, 'https://api.stripe.com/v1/invoices/in_sdk')
      .to_return(status: 200, body: '{"id":"in_sdk","object":"invoice"}',
                 headers: { 'Content-Type' => 'application/json' })
    100.times { expect(described_class.new.retrieve('invoice', 'in_sdk').fetch('id')).to eq('in_sdk') }
    expect(Stripe::StripeClient).to have_received(:new).once
  end

  it 'keeps clients separate across threads and replaces the slot when credentials change' do
    original = described_class.new.instance_variable_get(:@client)
    other = Thread.new { described_class.new.instance_variable_get(:@client) }.value
    expect(other).not_to equal(original)
    allow(StripeIntegration::Settings).to receive(:secret_key!).and_return('sk_test_rotated')
    replacement = described_class.new.instance_variable_get(:@client)
    expect(replacement).not_to equal(original)
    expect(described_class.new.instance_variable_get(:@client)).to equal(replacement)
  end

  it 'still validates configuration before using a previously cached client' do
    described_class.new
    allow(StripeIntegration::Settings).to receive(:secret_key!).and_raise(
      Billing::Error.new('stripe_unavailable', 'Missing test key.', status: 503)
    )
    expect { described_class.new }.to raise_error(StripeIntegration::Retryable, 'stripe_unavailable')
  end

  it 'sends the pinned API version, persisted payload and idempotency key through the actual SDK' do
    customer = create_customer
    gateway = described_class.new
    operations = StripeIntegration::Operations.new(gateway: gateway)
    operation = operations.prepare(key: "customer:#{customer.id}", kind: 'customer', customer: customer,
                                   payload: { email: customer.email })
    body = { id: 'cus_sdk', object: 'customer', livemode: false, email: customer.email,
             metadata: operation.payload.fetch('metadata') }
    request = stub_request(:post, 'https://api.stripe.com/v1/customers').with(
      headers: { 'Stripe-Version' => StripeIntegration::Settings::API_VERSION,
                 'Idempotency-Key' => operation.idempotency_key }, body: operation.payload
    ).to_return(status: 200, body: JSON.generate(body), headers: { 'Content-Type' => 'application/json' })
    operations.execute(operation)
    expect(request).to have_been_requested.once
    expect([operation.reload.status, operation.remote_id]).to eq(%w[succeeded cus_sdk])
  end

  it 'encodes an attached invoice item amount using the current SDK contract' do
    invoice = create_invoice
    operation = StripeIntegration::Operations.new(gateway: described_class.new).prepare(
      key: 'item:sdk', kind: 'item', customer: invoice.customer, invoice: invoice,
      line: invoice.invoice_line_items.create!(metric: 'api_calls', quantity: 10, unit_amount: 7, amount: 70),
      payload: { invoice: 'in_sdk', customer: 'cus_sdk', amount: 70, currency: 'usd', discountable: false }
    )
    response = operation.payload.merge('id' => 'ii_sdk', 'object' => 'invoiceitem', 'livemode' => false)
    request = stub_request(:post, 'https://api.stripe.com/v1/invoiceitems')
              .with(body: hash_including('invoice' => 'in_sdk', 'amount' => '70', 'discountable' => 'false'))
              .to_return(status: 200, body: JSON.generate(response), headers: { 'Content-Type' => 'application/json' })
    StripeIntegration::Operations.new(gateway: described_class.new).execute(operation)
    expect(request).to have_been_requested.once
  end

  it 'paginates beyond the first refund page' do
    headers = { 'Content-Type' => 'application/json' }
    first_page = { object: 'list', url: '/v1/refunds', has_more: true, data: [{ id: 're_first', object: 'refund' }] }
    last_page = { object: 'list', url: '/v1/refunds', has_more: false, data: [{ id: 're_last', object: 'refund' }] }
    first = stub_request(:get, 'https://api.stripe.com/v1/refunds')
            .with(query: { charge: 'ch_sdk', limit: '100' })
            .to_return(status: 200, body: JSON.generate(first_page), headers: headers)
    last = stub_request(:get, 'https://api.stripe.com/v1/refunds')
           .with(query: { charge: 'ch_sdk', limit: '100', starting_after: 're_first' })
           .to_return(status: 200, body: JSON.generate(last_page), headers: headers)
    expect(described_class.new.list('refund', charge: 'ch_sdk').pluck('id')).to eq(%w[re_first re_last])
    expect(first).to have_been_requested.once
    expect(last).to have_been_requested.once
  end

  it 'classifies SDK transport failures as retryable without leaking provider error bodies' do
    stub_request(:get, 'https://api.stripe.com/v1/invoices/in_sdk').to_timeout
    expect { described_class.new.retrieve('invoice', 'in_sdk') }
      .to raise_error(StripeIntegration::Retryable, 'stripe_unavailable')
  end
end
