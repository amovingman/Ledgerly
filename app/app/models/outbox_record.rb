class OutboxRecord < ApplicationRecord
  belongs_to :stripe_event, optional: true
  belongs_to :invoice_collection, optional: true

  def target
    stripe_event || invoice_collection
  end
end
