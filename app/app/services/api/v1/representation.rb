module Api
  module V1
    module Representation
      def self.customer(record)
        attributes(record, %i[id name email stripe_customer_id created_at])
      end

      def self.plan(record)
        attributes(record, %i[id name metric unit_amount currency billing_interval created_at])
      end

      def self.subscription(record)
        attributes(record, %i[id customer_id plan_id metric unit_amount currency status starts_at ends_at created_at])
      end

      def self.usage_event(record)
        attributes(record, %i[id customer_id subscription_id metric quantity occurred_at idempotency_key created_at])
      end

      def self.invoice_summary(record)
        attributes(record,
                   %i[id customer_id subscription_id period_start period_end currency amount status stripe_invoice_id
                      created_at])
      end

      def self.invoice(record)
        invoice_summary(record).merge(
          line_items: record.invoice_line_items.sort_by(&:id).map do |line|
            attributes(line, %i[id metric quantity unit_amount amount])
          end,
          journals: record.ledger_transactions.sort_by(&:id).map { |journal| journal_detail(journal) }
        )
      end

      def self.journal_detail(record)
        attributes(record, %i[id journal_type business_effect_key currency]).merge(
          entries: record.ledger_entries.sort_by(&:id).map { |entry| attributes(entry, %i[id account debit credit]) }
        )
      end
      private_class_method :journal_detail

      def self.attributes(record, fields)
        record.slice(*fields).transform_values { |value| value.respond_to?(:iso8601) ? value.iso8601(6) : value }
      end
      private_class_method :attributes
    end
  end
end
