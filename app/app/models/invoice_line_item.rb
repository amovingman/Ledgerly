# typed: true

class InvoiceLineItem < ApplicationRecord
  extend T::Sig

  belongs_to :invoice
  has_many :usage_events, dependent: :restrict_with_exception

  validates :quantity, :unit_amount, :amount, numericality: { only_integer: true, greater_than: 0 }
  validates :metric, presence: true

  sig { returns(T::Boolean) }
  def readonly?
    persisted?
  end
end
