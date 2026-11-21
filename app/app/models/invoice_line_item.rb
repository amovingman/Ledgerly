class InvoiceLineItem < ApplicationRecord
  belongs_to :invoice
  has_many :usage_events, dependent: :restrict_with_exception

  validates :quantity, :unit_amount, :amount, numericality: { only_integer: true, greater_than: 0 }
  validates :metric, presence: true

  def readonly?
    persisted?
  end
end
