require 'rails_helper'

RSpec.describe 'Core resource API' do
  let(:headers) { { 'Authorization' => 'Bearer request-test-key' } }

  before { authenticate_api }

  it 'creates and reads a normalized customer' do
    post '/api/v1/customers', params: { customer: { name: ' Acme ', email: 'BILLING@example.test' } },
                              headers: headers, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body.dig('data', 'id')
    get "/api/v1/customers/#{id}", headers: headers
    expect(response.parsed_body.fetch('data')).to include('name' => 'Acme', 'email' => 'billing@example.test')
  end

  it 'paginates customers in deterministic ID order' do
    first = create_customer
    second = create_customer
    get '/api/v1/customers', params: { page: '2', per_page: '1' }, headers: headers
    expect(response.parsed_body.fetch('data').pluck('id')).to eq([second.id])
    expect(response.parsed_body.fetch('meta')).to eq('page' => 2, 'per_page' => 1, 'total' => 2)
    expect(first.id).to be < second.id
  end

  it 'rejects a page size above the API limit' do
    get '/api/v1/customers', params: { per_page: '101' }, headers: headers
    expect(response).to have_http_status(:bad_request)
  end

  it 'returns a conflict for duplicate customer identity' do
    customer = create_customer
    post '/api/v1/customers', params: { customer: { name: 'Duplicate', email: customer.email } },
                              headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.dig('error', 'code')).to eq('resource_conflict')
  end

  it 'rejects malformed root shapes and invalid customer attributes' do
    post '/api/v1/customers', params: { customer: [] }, headers: headers, as: :json
    expect(response).to have_http_status(:bad_request)
    post '/api/v1/customers', params: { customer: { name: 'Acme', email: 'invalid' } }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'requires authentication before creating resources' do
    post '/api/v1/customers', params: { customer: { name: 'Acme', email: 'billing@example.test' } }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(Customer.count).to eq(0)
  end

  it 'creates, reads and lists metered plans' do
    post '/api/v1/plans', params: { plan: { name: 'Calls', metric: 'api_calls', unit_amount: 7, currency: 'USD' } },
                          headers: headers, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body.dig('data', 'id')
    get "/api/v1/plans/#{id}", headers: headers
    expect(response.parsed_body.fetch('data')).to include('unit_amount' => 7, 'billing_interval' => 'monthly')
    get '/api/v1/plans', headers: headers
    expect(response.parsed_body.fetch('data').pluck('id')).to eq([id])
  end

  [0, 1.5, '7', true].each do |price|
    it "rejects invalid plan price #{price.inspect}" do
      post '/api/v1/plans', params: { plan: { name: 'Calls', metric: 'calls', unit_amount: price, currency: 'USD' } },
                            headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(Plan.count).to eq(0)
    end
  end

  it 'creates a subscription using server-side price and lifecycle snapshots' do
    customer = create_customer
    plan = create_plan
    post '/api/v1/subscriptions', params: { subscription: { customer_id: customer.id, plan_id: plan.id,
                                                            starts_at: '2026-01-01T00:00:00Z', unit_amount: 1,
                                                            currency: 'CAD', status: 'cancelled' } },
                                  headers: headers, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body.dig('data', 'id')
    get "/api/v1/subscriptions/#{id}", headers: headers
    expect(response.parsed_body.fetch('data')).to include('unit_amount' => 7, 'currency' => 'USD', 'status' => 'active')
  end

  it 'exposes overlap conflicts and scoped reference validation' do
    subscription = create_subscription
    payload = { subscription: { customer_id: subscription.customer_id, plan_id: subscription.plan_id,
                                starts_at: '2026-01-01T00:00:00Z' } }
    post '/api/v1/subscriptions', params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.dig('error', 'code')).to eq('subscription_overlap')
    payload[:subscription][:customer_id] = '1garbage'
    post '/api/v1/subscriptions', params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'cancels subscriptions safely on repeat requests' do
    subscription = create_subscription
    post "/api/v1/subscriptions/#{subscription.id}/cancel", headers: headers
    original = response.parsed_body
    expect(response).to have_http_status(:ok)
    post "/api/v1/subscriptions/#{subscription.id}/cancel", headers: headers
    expect(response.parsed_body).to eq(original)
    expect(subscription.reload.status).to eq('cancelled')
  end

  it 'returns JSON when a referenced resource does not exist' do
    get '/api/v1/customers/9223372036854775807', headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body.dig('error', 'code')).to eq('not_found')
  end
end
