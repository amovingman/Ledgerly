class StripeEvent < ApplicationRecord
  has_one :outbox_record, dependent: :restrict_with_exception
  has_many :ledger_transactions, dependent: :restrict_with_exception
  attr_readonly :stripe_id, :event_type, :api_version, :raw_payload, :payload
  validates :stripe_id, :event_type, :api_version, :raw_payload, presence: true

  def terminal?
    %w[processed ignored dead review].include?(status)
  end
end
