module BillingHelpers
  def create_customer(**attributes)
    Customer.create!({ name: 'Example customer', email: "#{SecureRandom.hex(8)}@example.test" }.merge(attributes))
  end

  def create_plan(**attributes)
    Plan.create!({ name: 'API calls', metric: 'api_calls', unit_amount: 7, currency: 'USD' }.merge(attributes))
  end

  def create_subscription(customer: create_customer, plan: create_plan, **attributes)
    Subscription.create!({ customer: customer, plan: plan, metric: plan.metric, unit_amount: plan.unit_amount,
                           currency: plan.currency, starts_at: Time.utc(2026, 1, 1) }.merge(attributes))
  end

  def create_invoice(subscription: create_subscription, **attributes)
    Invoice.create!({ customer: subscription.customer, subscription: subscription, currency: subscription.currency,
                      period_start: Time.utc(2026, 1, 1),
                      period_end: Time.utc(2026, 2, 1), amount: 70 }.merge(attributes))
  end

  def create_usage(subscription:, **attributes)
    UsageEvent.create!({ customer: subscription.customer, subscription: subscription, metric: subscription.metric,
                         quantity: 10, occurred_at: Time.utc(2026, 1, 15), idempotency_key: SecureRandom.uuid,
                         request_fingerprint: 'a' * 64 }.merge(attributes))
  end

  def journal_attributes(invoice:, amount: invoice.amount)
    { invoice: invoice, currency: invoice.currency, journal_type: 'issuance',
      business_effect_key: "invoice:#{invoice.id}:issuance",
      ledger_entries: [LedgerEntry.new(account: 'accounts_receivable', debit: amount),
                       LedgerEntry.new(account: 'usage_revenue', credit: amount)] }
  end

  def ingest(subscription:, key: SecureRandom.uuid, **attributes)
    payload = { metric: subscription.metric, quantity: 10, occurred_at: '2026-01-15T00:00:00Z' }.merge(attributes)
    Billing::IngestUsage.new(customer: subscription.customer, subscription: subscription,
                             attributes: payload, idempotency_key: key).call
  end

  def generate_invoice(subscription:, period_start: '2026-01-01T00:00:00Z')
    Billing::GenerateInvoice.new(subscription: subscription, period_start: period_start).call
  end

  def authenticate_api
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('API_KEY').and_return('request-test-key')
  end

  def expect_database_rejection(constraint, &)
    expect { ApplicationRecord.transaction(requires_new: true, &) }
      .to raise_error(ActiveRecord::StatementInvalid, /#{constraint}/)
  end
end
