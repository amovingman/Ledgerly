require 'rails_helper'

RSpec.describe 'Usage ingestion API' do
  let(:subscription) { create_subscription }
  let(:headers) { { 'Authorization' => 'Bearer request-test-key', 'Idempotency-Key' => 'request-123' } }
  let(:payload) do
    { usage_event: { customer_id: subscription.customer_id, subscription_id: subscription.id,
                     metric: 'api_calls', quantity: 10, occurred_at: '2026-01-15T00:00:00.000001Z' } }
  end

  before { authenticate_api }

  it 'replays an immutable response and creates only one event' do
    post '/api/v1/usage_events', params: payload, headers: headers, as: :json
    first = response.parsed_body
    expect(response).to have_http_status(:created)
    post '/api/v1/usage_events', params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(first)
    expect(response.headers['Idempotency-Replayed']).to eq('true')
    expect(UsageEvent.count).to eq(1)
  end

  it 'returns a conflict for changed payloads' do
    post '/api/v1/usage_events', params: payload, headers: headers, as: :json
    payload[:usage_event][:quantity] = 11
    post '/api/v1/usage_events', params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.dig('error', 'code')).to eq('idempotency_conflict')
  end

  it 'requires an idempotency header' do
    post '/api/v1/usage_events', params: payload, headers: headers.except('Idempotency-Key'), as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig('error', 'code')).to eq('invalid_idempotency_key')
    expect(UsageEvent.count).to eq(0)
  end

  it 'does not attach usage to another customer subscription' do
    payload[:usage_event][:customer_id] = create_customer.id
    post '/api/v1/usage_events', params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(UsageEvent.count).to eq(0)
  end

  it 'rejects malformed JSON on the real ingestion route' do
    post '/api/v1/usage_events', params: '{', headers: headers.merge('CONTENT_TYPE' => 'application/json')
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body.dig('error', 'code')).to eq('invalid_json')
  end
end
