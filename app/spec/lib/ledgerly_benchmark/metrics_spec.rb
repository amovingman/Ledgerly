require 'rails_helper'

RSpec.describe LedgerlyBenchmark::Metrics do
  it 'reads actual event timing columns and protects observation endpoints with authentication' do
    stub_const('ENV', ENV.to_h.merge('API_KEY' => 'metrics-test-key'))
    StripeEvent.create!(stripe_id: 'evt_metrics', event_type: 'customer.updated', api_version: 'fixture',
                        raw_payload: '{}', payload: {}, status: 'processed', attempts: 1,
                        created_at: 3.seconds.ago, last_attempted_at: 2.seconds.ago, processed_at: 1.second.ago)
    api = Rack::MockRequest.new(described_class.new(->(_env) { [404, {}, []] }))
    expect(api.get('/_benchmark/stats').status).to eq(401)
    response = api.get('/_benchmark/stats', 'HTTP_AUTHORIZATION' => 'Bearer metrics-test-key')
    body = JSON.parse(response.body)
    expect(response.status).to eq(200)
    expect(body.values_at('total', 'processed', 'max_attempts')).to eq([1, 1, 1])
    expect(body.fetch('receipt_to_attempt_ms').first).to be > 900
  end
end
