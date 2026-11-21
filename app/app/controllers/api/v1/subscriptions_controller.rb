module Api
  module V1
    class SubscriptionsController < BaseController
      def show
        render json: { data: Representation.subscription(find_record(Subscription)) }
      end

      def create
        attributes = params.expect(subscription: %i[customer_id plan_id starts_at])
        record = Billing::Subscriptions.create(customer: find_record(Customer, attributes[:customer_id]),
                                               plan: find_record(Plan, attributes[:plan_id]),
                                               starts_at: attributes[:starts_at])
        render json: { data: Representation.subscription(record) }, status: :created
      end

      def cancel
        record = Billing::Subscriptions.cancel(subscription: find_record(Subscription))
        render json: { data: Representation.subscription(record) }
      end
    end
  end
end
