class LedgerEntry < ApplicationRecord
  ACCOUNTS = %w[accounts_receivable usage_revenue stripe_clearing sales_returns].freeze
  belongs_to :ledger_transaction, inverse_of: :ledger_entries

  validates :account, inclusion: { in: ACCOUNTS }
  validates :debit, :credit, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :exactly_one_side

  def readonly?
    persisted?
  end

  private

  def exactly_one_side
    valid = (debit.to_i.positive? && credit.zero?) || (credit.to_i.positive? && debit.zero?)
    errors.add(:base, 'exactly one of debit or credit must be positive') unless valid
  end
end
