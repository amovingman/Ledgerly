require 'webmock/rspec'
Sidekiq.testing!(:fake)
WebMock.disable_net_connect!(allow_localhost: true)

module StripeHelpers
  WEBHOOK_SECRET = 'whsec_fixture'.freeze

  def configure_stripe_test
    allow(StripeIntegration::Settings).to receive_messages(secret_key!: 'sk_test_fixture',
                                                           webhook_secret!: WEBHOOK_SECRET)
  end

  def stripe_payload(type: 'invoice.paid', object_id: 'in_fixture', **attributes)
    { 'id' => "evt_#{SecureRandom.hex(8)}", 'object' => 'event', 'type' => type,
      'api_version' => StripeIntegration::Settings::API_VERSION, 'livemode' => false, 'created' => Time.now.to_i,
      'data' => { 'object' => { 'id' => object_id, 'object' => type.start_with?('charge.') ? 'charge' : 'invoice' } } }
      .merge(attributes.stringify_keys)
  end

  def sign_stripe(raw, timestamp: Time.zone.now)
    digest = Stripe::Webhook::Signature.compute_signature(timestamp, raw, WEBHOOK_SECRET)
    Stripe::Webhook::Signature.generate_header(timestamp, digest)
  end

  def receive_stripe(payload)
    raw = JSON.generate(payload)
    StripeIntegration::ReceiveEvent.call(raw: raw, signature: sign_stripe(raw)).record
  end

  def paid_stripe_invoice(refunds: [])
    subscription = create_subscription
    create_usage(subscription: subscription)
    invoice = generate_invoice(subscription: subscription).record
    invoice.customer.update!(stripe_customer_id: "cus_#{invoice.customer_id}")
    invoice.update!(stripe_invoice_id: "in_#{invoice.id}")
    gateway = FakeStripeGateway.new
    gateway.seed_paid(invoice, refunds: refunds)
    [invoice, gateway]
  end

  def process_stripe(event, gateway)
    StripeIntegration::ProcessEvent.new(event: event, gateway: gateway).call
  end

  def clean_billing_data
    models = [OutboxRecord, StripeRefund, StripePayment, LedgerEntry, LedgerTransaction, StripeOperation,
              InvoiceCollection, StripeEvent, UsageEvent, InvoiceLineItem, Invoice, Subscription, Plan, Customer]
    models.each(&:delete_all)
  end
end

RSpec.configure do |config|
  config.include StripeHelpers
  config.before do
    [StripeIntegration::ProcessEventJob, StripeIntegration::CollectInvoiceJob].each(&:clear)
  end
end
