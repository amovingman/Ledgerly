class Invoice < ApplicationRecord
  belongs_to :customer
  belongs_to :subscription
  has_many :invoice_line_items, dependent: :restrict_with_exception
  has_many :ledger_transactions, dependent: :restrict_with_exception

  attr_readonly :customer_id, :subscription_id, :period_start, :period_end, :currency, :amount
  validates :amount, numericality: { only_integer: true, greater_than: 0 }
  validates :currency, inclusion: { in: Plan::CURRENCIES }
  validates :status, inclusion: { in: %w[issued paid payment_failed refunded] }
  validates :period_start, :period_end, presence: true
end
