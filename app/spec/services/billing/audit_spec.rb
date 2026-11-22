require 'rails_helper'

RSpec.describe Billing::Audit, :concurrency do
  self.use_transactional_tests = false

  around do |example|
    clean_billing_data
    example.run
  ensure
    clean_billing_data
  end

  def issued_invoice
    subscription = create_subscription
    create_usage(subscription: subscription)
    generate_invoice(subscription: subscription).record
  end

  it 'accepts real billing data without benchmark fixture counts or a fixed usage-event count' do
    invoice = issued_invoice
    version = invoice.customer.reload.read_version
    expect(described_class.call.values).to all(eq(0))
    expect(invoice.customer.reload.read_version).to eq(version)
  end

  it 'detects journal corruption introduced by administrative SQL beyond row-level checks' do
    invoice = issued_invoice
    entry = invoice.ledger_transactions.first.ledger_entries.find_by!(account: 'usage_revenue')
    LedgerEntry.where(id: entry.id).update_all(credit: entry.credit + 1) # rubocop:disable Rails/SkipsModelValidations
    expect(described_class.call[:journal_balance]).to eq(1)
  end

  it 'detects a missing usage allocation even when every financial journal still balances' do
    invoice = issued_invoice
    event = invoice.invoice_line_items.first.usage_events.first
    event.update_columns(invoice_line_item_id: nil) # rubocop:disable Rails/SkipsModelValidations
    checks = described_class.call
    expect(checks[:usage_allocations]).to eq(1)
    expect(checks[:journal_balance]).to eq(0)
  end
end
