module Api
  module V1
    class UsageEventsController < BaseController
      def create
        render_result(ingestion_result, :usage_event)
      end

      private

      def ingestion_result
        attributes = params.expect(usage_event: %i[customer_id subscription_id metric quantity occurred_at])
        customer = find_record(Customer, attributes[:customer_id])
        subscription = customer.subscriptions.find(Billing::Input.identifier(attributes[:subscription_id]))
        Billing::IngestUsage.new(customer: customer, subscription: subscription, attributes: attributes,
                                 idempotency_key: request.headers['Idempotency-Key']).call
      end
    end
  end
end
