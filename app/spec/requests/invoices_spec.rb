require 'rails_helper'

RSpec.describe 'Invoices and balance API' do
  let(:headers) { { 'Authorization' => 'Bearer request-test-key' } }

  before { authenticate_api }

  it 'issues, replays and reads an auditable invoice' do
    subscription = create_subscription
    create_usage(subscription: subscription)
    payload = { invoice: { period_start: '2026-01-01T00:00:00Z', amount: 1, currency: 'CAD' } }
    post "/api/v1/subscriptions/#{subscription.id}/invoices", params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    original = response.parsed_body.fetch('data')
    expect(original).to include('amount' => 70, 'currency' => 'USD')
    post "/api/v1/subscriptions/#{subscription.id}/invoices", params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.headers['Idempotency-Replayed']).to eq('true')
    get "/api/v1/invoices/#{original.fetch('id')}", headers: headers
    expect(response.parsed_body.fetch('data')).to eq(original)
  end

  it 'paginates customer invoices with an ID tiebreaker' do
    subscription = create_subscription
    create_usage(subscription: subscription)
    create_usage(subscription: subscription, occurred_at: Time.utc(2026, 2, 1))
    travel_to(Time.utc(2026, 4, 1)) do
      january = generate_invoice(subscription: subscription).record
      february = generate_invoice(subscription: subscription, period_start: '2026-02-01T00:00:00Z').record
      get "/api/v1/customers/#{subscription.customer_id}/invoices", params: { per_page: '1' }, headers: headers
      expect(response.parsed_body.fetch('data').pluck('id')).to eq([february.id])
      get "/api/v1/customers/#{subscription.customer_id}/invoices", params: { page: '2', per_page: '1' },
                                                                    headers: headers
      expect(response.parsed_body.fetch('data').pluck('id')).to eq([january.id])
    end
  end

  it 'keeps invoice lists scoped to their customer' do
    invoice = create_invoice
    customer = create_customer
    get "/api/v1/customers/#{customer.id}/invoices", headers: headers
    expect(response.parsed_body.fetch('data')).to eq([])
    get "/api/v1/customers/#{invoice.customer_id}/invoices", headers: headers
    expect(response.parsed_body.fetch('data').pluck('id')).to eq([invoice.id])
  end

  it 'reports separate ledger-derived receivables in each currency' do
    subscription = create_subscription
    other = create_subscription(customer: subscription.customer, plan: create_plan(currency: 'CAD', metric: 'storage'))
    create_usage(subscription: subscription)
    create_usage(subscription: other, quantity: 5)
    generate_invoice(subscription: subscription)
    generate_invoice(subscription: other)
    get "/api/v1/customers/#{subscription.customer_id}/balance", headers: headers
    expected = [{ 'currency' => 'CAD', 'amount' => 35 }, { 'currency' => 'USD', 'amount' => 70 }]
    expect(response.parsed_body.dig('data', 'balances')).to eq(expected)
  end

  it 'uses ledger postings rather than invoice status to calculate the balance' do
    subscription = create_subscription
    create_usage(subscription: subscription)
    invoice = generate_invoice(subscription: subscription).record
    payment = journal_attributes(invoice: invoice).merge(journal_type: 'payment', business_effect_key: 'test:payment')
    payment[:ledger_entries] = [LedgerEntry.new(account: 'stripe_clearing', debit: 70),
                                LedgerEntry.new(account: 'accounts_receivable', credit: 70)]
    LedgerTransaction.create!(**payment)
    get "/api/v1/customers/#{subscription.customer_id}/balance", headers: headers
    expect(response.parsed_body.dig('data', 'balances')).to eq([{ 'currency' => 'USD', 'amount' => 0 }])
    expect(invoice.reload.status).to eq('issued')
  end

  it 'returns an empty balance for customers without postings' do
    customer = create_customer
    get "/api/v1/customers/#{customer.id}/balance", headers: headers
    expect(response.parsed_body.dig('data', 'balances')).to eq([])
  end

  it 'rejects new late usage after real issuance while preserving original replay bodies' do
    subscription = create_subscription
    payload = { usage_event: { customer_id: subscription.customer_id, subscription_id: subscription.id,
                               metric: 'api_calls', quantity: 10, occurred_at: '2026-01-15T00:00:00Z' } }
    usage_headers = headers.merge('Idempotency-Key' => 'original-key')
    post '/api/v1/usage_events', params: payload, headers: usage_headers, as: :json
    original = response.parsed_body
    generate_invoice(subscription: subscription)
    post '/api/v1/usage_events', params: payload, headers: usage_headers, as: :json
    expect(response.parsed_body).to eq(original)
    post '/api/v1/usage_events', params: payload, headers: headers.merge('Idempotency-Key' => 'late-key'), as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.dig('error', 'code')).to eq('usage_period_closed')
  end
end
