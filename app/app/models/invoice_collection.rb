# typed: true

class InvoiceCollection < ApplicationRecord
  extend T::Sig

  belongs_to :invoice
  has_one :outbox_record, dependent: :restrict_with_exception

  sig { returns(T::Boolean) }
  def terminal?
    %w[succeeded dead review].include?(status)
  end
end
