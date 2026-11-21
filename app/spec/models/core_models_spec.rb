require 'rails_helper'

RSpec.describe 'Core billing models' do
  it 'normalizes customer identity and rejects invalid email addresses' do
    customer = create_customer(email: ' Example@EXAMPLE.test ', name: ' Example ')
    expect([customer.name, customer.email]).to eq(['Example', 'example@example.test'])
    expect(Customer.new(name: 'Example', email: 'invalid')).not_to be_valid
  end

  it 'requires a supported currency and positive integral plan price' do
    plan = Plan.new(name: 'Bad', metric: 'api_calls', currency: 'XYZ', unit_amount: 1.5)
    expect(plan).not_to be_valid
    expect(plan.errors.attribute_names).to include(:currency, :unit_amount)
  end

  it 'requires cancellation to have an effective end timestamp' do
    subscription = create_subscription
    subscription.status = 'cancelled'
    expect(subscription).not_to be_valid
    expect(subscription.errors[:ends_at]).to be_present
  end

  it 'creates a balanced complete journal' do
    journal = LedgerTransaction.create!(**journal_attributes(invoice: create_invoice))
    expect(journal.ledger_entries.sum(:debit)).to eq(journal.ledger_entries.sum(:credit))
    expect(journal.ledger_entries.count).to eq(2)
  end

  it 'rejects unbalanced journals before persisting any rows' do
    attributes = journal_attributes(invoice: create_invoice)
    attributes[:ledger_entries].last.credit -= 1
    expect { LedgerTransaction.create!(**attributes) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(LedgerTransaction.count).to eq(0)
    expect(LedgerEntry.count).to eq(0)
  end

  it 'rejects a journal in a different currency from its invoice' do
    journal = LedgerTransaction.new(**journal_attributes(invoice: create_invoice), currency: 'CAD')
    expect(journal).not_to be_valid
    expect(journal.errors[:currency]).to be_present
  end

  it 'rejects two-sided ledger entries at the model layer' do
    entry = LedgerEntry.new(account: 'accounts_receivable', debit: 1, credit: 1)
    expect(entry).not_to be_valid
    expect(entry.errors[:base]).to be_present
  end

  it 'keeps posted journal entries read-only through the models' do
    journal = LedgerTransaction.create!(**journal_attributes(invoice: create_invoice))
    expect { journal.update!(business_effect_key: 'changed') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { journal.ledger_entries.first.update!(debit: 50) }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end
end
