# typed: true

class Subscription < ApplicationRecord
  extend T::Sig

  belongs_to :customer
  belongs_to :plan
  has_many :usage_events, dependent: :restrict_with_exception
  has_many :invoices, dependent: :restrict_with_exception

  attr_readonly :customer_id, :plan_id, :metric, :unit_amount, :currency, :starts_at
  validates :metric, format: { with: /\A[a-z][a-z0-9_]{0,63}\z/ }
  validates :unit_amount, numericality: { only_integer: true, in: 1..1_000_000_000 }
  validates :currency, inclusion: { in: Plan::CURRENCIES }
  validates :starts_at, presence: true
  validates :status, inclusion: { in: %w[active cancelled] }
  validate :valid_lifecycle

  private

  sig { void }
  def valid_lifecycle
    finish = ends_at
    valid = status == 'active' ? finish.nil? : !finish.nil? && starts_at.present? && finish >= starts_at
    errors.add(:ends_at, 'does not match the subscription lifecycle') unless valid
  end
end
