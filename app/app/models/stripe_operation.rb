class StripeOperation < ApplicationRecord
  belongs_to :customer
  belongs_to :invoice, optional: true
  belongs_to :invoice_line_item, optional: true
  attr_readonly :customer_id, :invoice_id, :invoice_line_item_id, :operation_key, :idempotency_key, :kind, :payload
  validates :operation_key, :idempotency_key, :kind, presence: true
  validate :preserve_first_attempt

  private

  def preserve_first_attempt
    return unless persisted? && first_attempted_at_changed? && first_attempted_at_was.present?

    errors.add(:first_attempted_at, 'cannot be reset')
  end
end
