# typed: true

class OutboxRecord < ApplicationRecord
  extend T::Sig

  belongs_to :stripe_event, optional: true
  belongs_to :invoice_collection, optional: true

  sig { returns(T.nilable(T.any(StripeEvent, InvoiceCollection))) }
  def target
    stripe_event || invoice_collection
  end
end
