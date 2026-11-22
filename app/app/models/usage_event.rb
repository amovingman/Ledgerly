# typed: true

class UsageEvent < ApplicationRecord
  extend T::Sig

  belongs_to :customer
  belongs_to :subscription
  belongs_to :invoice_line_item, optional: true

  attr_readonly :customer_id, :subscription_id, :metric, :quantity, :occurred_at, :idempotency_key, :request_fingerprint
  validates :quantity, numericality: { only_integer: true, in: 1..1_000_000_000 }
  validates :occurred_at, presence: true
  validates :idempotency_key, format: { with: /\A[A-Za-z0-9._:-]{1,128}\z/ }
  validates :request_fingerprint, format: { with: /\A[a-f0-9]{64}\z/ }
  validate :allocation_is_final

  private

  sig { void }
  def allocation_is_final
    return unless persisted? && invoice_line_item_id_changed? && invoice_line_item_id_was.present?

    errors.add(:invoice_line_item, 'cannot be reassigned')
  end
end
