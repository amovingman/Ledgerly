module Api
  module V1
    class CustomersController < BaseController
      def index
        render_collection(Customer.order(:id), :customer)
      end

      def show
        render json: { data: Representation.customer(find_record(Customer)) }
      end

      def create
        attributes = params.expect(customer: %i[name email])
        record = Customer.create!(name: Billing::Input.text(attributes[:name], field: 'name'),
                                  email: Billing::Input.text(attributes[:email], field: 'email', maximum: 254))
        render json: { data: Representation.customer(record) }, status: :created
      end
    end
  end
end
