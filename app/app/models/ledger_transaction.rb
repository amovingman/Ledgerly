# typed: true

class LedgerTransaction < ApplicationRecord
  extend T::Sig

  belongs_to :invoice
  belongs_to :stripe_event, optional: true
  has_many :ledger_entries, inverse_of: :ledger_transaction, autosave: true, dependent: :restrict_with_exception

  after_create :advance_read_version

  validates :journal_type, inclusion: { in: %w[issuance payment refund] }
  validates :business_effect_key, presence: true
  validates :currency, inclusion: { in: Plan::CURRENCIES }
  validate :balanced_journal
  validate :invoice_currency

  sig { returns(T::Boolean) }
  def readonly?
    persisted?
  end

  private

  sig { void }
  def advance_read_version
    Billing::ReadVersion.advance!(T.must(invoice).customer_id)
  end

  sig { void }
  def balanced_journal
    entries = ledger_entries.to_a
    return if entries.size >= 2 && entries.sum { |entry| entry.debit.to_i } == entries.sum { |entry| entry.credit.to_i }

    errors.add(:ledger_entries, 'must contain at least two balanced entries')
  end

  sig { void }
  def invoice_currency
    record = invoice
    errors.add(:currency, 'must match the invoice') if record && currency != record.currency
  end
end
