# typed: true

class Invoice < ApplicationRecord
  extend T::Sig

  belongs_to :customer
  belongs_to :subscription
  has_one :invoice_collection, dependent: :restrict_with_exception
  has_one :stripe_payment, dependent: :restrict_with_exception
  has_many :stripe_operations, dependent: :restrict_with_exception
  has_many :invoice_line_items, dependent: :restrict_with_exception
  has_many :ledger_transactions, dependent: :restrict_with_exception

  after_create :advance_read_version
  after_update :advance_read_version, if: :summary_changed?

  attr_readonly :customer_id, :subscription_id, :period_start, :period_end, :currency, :amount
  validates :amount, numericality: { only_integer: true, greater_than: 0 }
  validates :currency, inclusion: { in: Plan::CURRENCIES }
  validates :status, inclusion: { in: %w[issued paid payment_failed refunded] }
  validates :period_start, :period_end, presence: true

  private

  sig { returns(T::Boolean) }
  def summary_changed?
    saved_change_to_status? || saved_change_to_stripe_invoice_id?
  end

  sig { void }
  def advance_read_version
    Billing::ReadVersion.advance!(customer_id)
  end
end
