class InvoiceCollection < ApplicationRecord
  belongs_to :invoice
  has_one :outbox_record, dependent: :restrict_with_exception

  def terminal?
    %w[succeeded dead review].include?(status)
  end
end
