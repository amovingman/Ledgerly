class LedgerTransaction < ApplicationRecord
  belongs_to :invoice
  has_many :ledger_entries, inverse_of: :ledger_transaction, autosave: true, dependent: :restrict_with_exception

  validates :journal_type, inclusion: { in: %w[issuance payment refund] }
  validates :business_effect_key, presence: true
  validates :currency, inclusion: { in: Plan::CURRENCIES }
  validate :balanced_journal
  validate :invoice_currency

  def readonly?
    persisted?
  end

  private

  def balanced_journal
    entries = ledger_entries.to_a
    return if entries.size >= 2 && entries.sum { |entry| entry.debit.to_i } == entries.sum { |entry| entry.credit.to_i }

    errors.add(:ledger_entries, 'must contain at least two balanced entries')
  end

  def invoice_currency
    errors.add(:currency, 'must match the invoice') if invoice && currency != invoice.currency
  end
end
