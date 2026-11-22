module StripeIntegration
  module RequestCollection
    def self.call(invoice:)
      Settings.secret_key!
      invoice.customer.with_lock do
        invoice.reload
        existing = invoice.invoice_collection
        return existing if existing

        validate!(invoice)
        collection = InvoiceCollection.create!(invoice: invoice)
        OutboxRecord.create!(invoice_collection: collection, available_at: Time.current)
        collection
      end
    end

    def self.validate!(invoice)
      validate_amount!(invoice)
      if invoice.stripe_invoice_id.present? || invoice.stripe_payment || invoice.status != 'issued'
        raise Billing::Error.new('invoice_already_collected', 'This invoice cannot start another collection.',
                                 status: 409)
      end
      return if invoice.ledger_transactions.exists?(journal_type: 'issuance')

      raise Billing::Error.new('missing_issuance', 'Issue the local invoice before requesting collection.')
    end

    def self.validate_amount!(invoice)
      return if (Settings::MINIMUMS.fetch(invoice.currency)..Settings::COLLECTION_LIMIT).cover?(invoice.amount)

      raise Billing::Error.new('unsupported_collection_amount',
                               'The amount is outside the configured collection range.')
    end
    private_class_method :validate!, :validate_amount!
  end
end
