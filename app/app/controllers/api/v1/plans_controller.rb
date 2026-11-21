module Api
  module V1
    class PlansController < BaseController
      def index
        render_collection(Plan.order(:id), :plan)
      end

      def show
        render json: { data: Representation.plan(find_record(Plan)) }
      end

      def create
        record = Plan.create!(validated_attributes)
        render json: { data: Representation.plan(record) }, status: :created
      end

      private

      def validated_attributes
        attributes = params.expect(plan: %i[name metric unit_amount currency])
        { name: Billing::Input.text(attributes[:name], field: 'name'),
          metric: Billing::Input.text(attributes[:metric], field: 'metric', maximum: 64),
          unit_amount: Billing::Input.positive_integer(attributes[:unit_amount], field: 'unit_amount',
                                                                                 maximum: 1_000_000_000),
          currency: Billing::Input.text(attributes[:currency], field: 'currency', maximum: 3) }
      end
    end
  end
end
