require 'rails_helper'

RSpec.describe 'Stripe webhook endpoint' do
  before { configure_stripe_test }

  def deliver(raw, signature: sign_stripe(raw))
    post '/webhooks/stripe', params: raw,
                             headers: { 'CONTENT_TYPE' => 'application/json', 'Stripe-Signature' => signature }
  end

  it 'verifies exact bytes, persists the raw receipt and queues one job without API-key auth' do
    raw = JSON.pretty_generate(stripe_payload)
    deliver(raw)
    expect(response).to have_http_status(:ok)
    expect(StripeEvent.sole.raw_payload).to eq(raw)
    expect(OutboxRecord.count).to eq(1)
    expect(StripeIntegration::ProcessEventJob.jobs.size).to eq(1)
    deliver(raw)
    expect(response.parsed_body).to eq('received' => true, 'duplicate' => true)
  end

  it 'rejects changed bytes and expired signatures before storing anything' do
    raw = JSON.generate(stripe_payload)
    deliver("#{raw} ", signature: sign_stripe(raw))
    expect(response).to have_http_status(:bad_request)
    deliver(raw, signature: sign_stripe(raw, timestamp: 10.minutes.ago))
    expect(response).to have_http_status(:bad_request)
    expect([StripeEvent.count, OutboxRecord.count]).to eq([0, 0])
  end

  it 'rejects live, connected-account and wrong-version receipts' do
    [{ livemode: true }, { account: 'acct_other' }, { api_version: '2025-09-30.clover' }].each do |attributes|
      deliver(JSON.generate(stripe_payload(**attributes)))
      expect(response).to have_http_status(:bad_request)
    end
    expect(StripeEvent.count).to eq(0)
  end

  it 'keeps a durable pending receipt and still acknowledges when Redis is unavailable' do
    allow(StripeIntegration::ProcessEventJob).to receive(:perform_async).and_raise(RedisClient::CannotConnectError)
    deliver(JSON.generate(stripe_payload))
    expect(response).to have_http_status(:ok)
    expect(StripeEvent.count).to eq(1)
    expect(OutboxRecord.sole.dispatched_at).to be_nil
    expect(OutboxRecord.sole.last_error).to eq('queue_unavailable')
  end

  it 'accepts equivalent JSON formatting but rejects conflicting content under one event ID' do
    payload = stripe_payload
    deliver(JSON.generate(payload))
    deliver(JSON.pretty_generate(payload))
    expect(response).to have_http_status(:ok)
    payload['data']['object']['id'] = 'in_different'
    deliver(JSON.generate(payload))
    expect(response).to have_http_status(:conflict)
    expect(StripeEvent.count).to eq(1)
  end

  it 'rolls back receipt storage when its dispatch intent cannot be persisted' do
    allow(OutboxRecord).to receive(:create!).and_raise('injected storage failure')
    expect { receive_stripe(stripe_payload) }.to raise_error(RuntimeError, 'injected storage failure')
    expect(StripeEvent.count).to eq(0)
  end

  it 'fails closed when no webhook signing secret is configured' do
    allow(StripeIntegration::Settings).to receive(:webhook_secret!).and_call_original
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('STRIPE_WEBHOOK_SECRET').and_return(nil)
    deliver(JSON.generate(stripe_payload))
    expect(response).to have_http_status(:service_unavailable)
    expect(StripeEvent.count).to eq(0)
  end
end
