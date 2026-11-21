class Plan < ApplicationRecord
  CURRENCIES = %w[USD CAD EUR GBP].freeze
  has_many :subscriptions, dependent: :restrict_with_exception

  validates :name, presence: true, length: { maximum: 200 }
  validates :metric, format: { with: /\A[a-z][a-z0-9_]{0,63}\z/ }
  validates :unit_amount, numericality: { only_integer: true, in: 1..1_000_000_000 }
  validates :currency, inclusion: { in: CURRENCIES }
  validates :billing_interval, inclusion: { in: ['monthly'] }
end
