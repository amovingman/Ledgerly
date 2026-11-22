# typed: true

class StripePayment < ApplicationRecord
  extend T::Sig

  belongs_to :invoice
  belongs_to :ledger_transaction
  has_many :stripe_refunds, dependent: :restrict_with_exception
  validates :amount, numericality: { only_integer: true, greater_than: 0 }
  validates :charge_id, :payment_intent_id, :invoice_payment_id, presence: true

  sig { returns(T::Boolean) }
  def readonly?
    persisted?
  end
end
