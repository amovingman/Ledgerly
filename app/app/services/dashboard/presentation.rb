module Dashboard
  module Presentation
    def self.fields(record, names)
      record.slice(*names).transform_values { |value| value.respond_to?(:iso8601) ? value.iso8601(6) : value }
    end

    def self.customers(record)
      fields(record, %i[name email created_at]).merge(id: record.id.to_s,
                                                      stripe_customer_id: record.stripe_customer_id)
    end

    def self.usage(record)
      fields(record, %i[metric occurred_at]).merge(id: record.id.to_s, customer_id: record.customer_id.to_s,
                                                   customer_name: record.customer.name, quantity: record.quantity.to_s,
                                                   invoice_id: record.invoice_line_item&.invoice_id&.to_s,
                                                   status: record.invoice_line_item_id ? 'billed' : 'unbilled')
    end

    def self.invoices(record)
      fields(record, %i[period_start period_end currency status created_at stripe_invoice_id])
        .merge(id: record.id.to_s, customer_id: record.customer_id.to_s,
               customer_name: record.customer.name, amount: record.amount.to_s)
    end

    def self.ledger(record) # rubocop:disable Metrics/AbcSize -- Declarative read-only field mapping.
      journal = record.ledger_transaction
      fields(record, %i[account created_at]).merge(id: record.id.to_s, journal_id: journal.id.to_s,
                                                   journal_type: journal.journal_type, currency: journal.currency,
                                                   invoice_id: journal.invoice_id.to_s,
                                                   customer_id: journal.invoice.customer_id.to_s,
                                                   debit: record.debit.to_s, credit: record.credit.to_s,
                                                   business_effect_key: journal.business_effect_key)
    end

    def self.webhooks(record)
      fields(record, %i[stripe_id event_type api_version status attempts last_error last_attempted_at
                        processed_at created_at]).merge(id: record.id.to_s,
                                                        dispatched_at: record.outbox_record&.dispatched_at&.iso8601(6))
    end
  end
end
