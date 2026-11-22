# typed: true

class StripeRefund < ApplicationRecord
  extend T::Sig

  belongs_to :stripe_payment
  belongs_to :ledger_transaction
  validates :amount, numericality: { only_integer: true, greater_than: 0 }
  validates :stripe_id, presence: true

  sig { returns(T::Boolean) }
  def readonly?
    persisted?
  end
end
