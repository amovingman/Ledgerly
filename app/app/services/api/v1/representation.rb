module Api
  module V1
    module Representation
      def self.customer(record)
        attributes(record, %i[id name email created_at])
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

      def self.attributes(record, fields)
        record.slice(*fields).transform_values { |value| value.respond_to?(:iso8601) ? value.iso8601(6) : value }
      end
      private_class_method :attributes
    end
  end
end
