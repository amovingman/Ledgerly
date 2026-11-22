require 'rails_helper'

RSpec.describe 'Asynchronous Stripe collection API' do
  let(:headers) { { 'Authorization' => 'Bearer request-test-key' } }
  let(:invoice) do
    subscription = create_subscription
    create_usage(subscription: subscription)
    generate_invoice(subscription: subscription).record
  end

  before do
    authenticate_api
    configure_stripe_test
  end

  it 'persists and queues one request while exposing its status without making a Stripe call' do
    post "/api/v1/invoices/#{invoice.id}/collection", headers: headers
    expect(response).to have_http_status(:accepted)
    post "/api/v1/invoices/#{invoice.id}/collection", headers: headers
    expect([InvoiceCollection.count, OutboxRecord.count, StripeOperation.count]).to eq([1, 1, 0])
    expect(StripeIntegration::CollectInvoiceJob.jobs.size).to eq(1)
    get "/api/v1/invoices/#{invoice.id}/collection", headers: headers
    expect(response.parsed_body.fetch('data')).to include('invoice_id' => invoice.id, 'status' => 'pending')
  end

  it 'fails closed for missing or live-mode keys before persisting a collection' do
    allow(StripeIntegration::Settings).to receive(:secret_key!).and_call_original
    allow(ENV).to receive(:[]).with('STRIPE_SECRET_KEY').and_return('sk_live_rejected')
    post "/api/v1/invoices/#{invoice.id}/collection", headers: headers
    expect(response).to have_http_status(:service_unavailable)
    expect(InvoiceCollection.count).to eq(0)
  end

  it 'keeps collection intent durable when the queue is unavailable' do
    allow(StripeIntegration::CollectInvoiceJob).to receive(:perform_async).and_raise(RedisClient::CannotConnectError)
    post "/api/v1/invoices/#{invoice.id}/collection", headers: headers
    expect(response).to have_http_status(:accepted)
    expect(OutboxRecord.sole.dispatched_at).to be_nil
  end

  it 'exposes event processing metadata without disclosing the raw payment payload' do
    event = receive_stripe(stripe_payload)
    get "/api/v1/stripe_events/#{event.stripe_id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('data')).to include('status' => 'received')
    expect(response.parsed_body.fetch('data')).not_to have_key('raw_payload')
  end
end
