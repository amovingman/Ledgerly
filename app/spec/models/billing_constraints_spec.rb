require 'rails_helper'

RSpec.describe 'Billing database constraints' do
  it 'prevents duplicate customer emails even when model validation is bypassed' do
    customer = create_customer
    expect_database_rejection('customers_unique_email') do
      create_customer.update_columns(email: customer.email.upcase)
    end
  end

  it 'rejects overlapping customer and metric subscriptions in PostgreSQL' do
    subscription = create_subscription
    expect_database_rejection('subscriptions_no_overlap') do
      create_subscription(customer: subscription.customer, starts_at: subscription.starts_at + 1.day)
    end
  end

  it 'allows adjacent subscription intervals' do
    subscription = create_subscription(status: 'cancelled', ends_at: Time.utc(2026, 2, 1))
    replacement = create_subscription(customer: subscription.customer, starts_at: subscription.ends_at)
    expect(replacement).to be_persisted
  end

  it 'allows overlapping subscriptions for different metrics' do
    subscription = create_subscription
    other = create_subscription(customer: subscription.customer, plan: create_plan(metric: 'storage_bytes'))
    expect(other).to be_persisted
  end

  it 'rejects zero quantities without model validation' do
    event = create_usage(subscription: create_subscription)
    expect_database_rejection('usage_positive_quantity') { UsageEvent.where(id: event.id).update_all(quantity: 0) }
  end

  it 'prevents usage from referencing another customer subscription' do
    event = create_usage(subscription: create_subscription)
    other = create_customer
    expect_database_rejection('usage_subscription_identity') do
      UsageEvent.where(id: event.id).update_all(customer_id: other.id)
    end
  end

  it 'enforces usage idempotency uniqueness in the customer scope' do
    event = create_usage(subscription: create_subscription)
    expect_database_rejection('index_usage_events_on_customer_id_and_idempotency_key') do
      create_usage(subscription: event.subscription, idempotency_key: event.idempotency_key)
    end
  end

  it 'prevents multiple invoices for one subscription month' do
    invoice = create_invoice
    expect_database_rejection('index_invoices_on_subscription_id_and_period_start') do
      create_invoice(subscription: invoice.subscription)
    end
  end

  it 'requires a full calendar month in PostgreSQL' do
    invoice = create_invoice
    expect_database_rejection('invoices_calendar_month') do
      Invoice.where(id: invoice.id).update_all(period_end: invoice.period_end - 1.second)
    end
  end

  it 'prevents invoices from referencing another customer subscription' do
    invoice = create_invoice
    customer = create_customer
    expect_database_rejection('invoices_subscription_identity') do
      Invoice.where(id: invoice.id).update_all(customer_id: customer.id)
    end
  end

  it 'enforces exact invoice line multiplication' do
    invoice = create_invoice
    expect_database_rejection('invoice_lines_exact_amount') do
      invoice.invoice_line_items.create!(metric: 'api_calls', quantity: 10, unit_amount: 7, amount: 69)
    end
  end

  it 'prevents a ledger row from having two positive sides' do
    journal = LedgerTransaction.create!(**journal_attributes(invoice: create_invoice))
    entry = journal.ledger_entries.first
    expect_database_rejection('ledger_one_side') { LedgerEntry.where(id: entry.id).update_all(credit: 1) }
  end
end
