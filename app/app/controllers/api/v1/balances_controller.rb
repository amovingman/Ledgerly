module Api
  module V1
    class BalancesController < BaseController
      def show
        customer = find_record(Customer, params[:customer_id])
        render json: { data: { customer_id: customer.id, balances: Billing::CustomerBalance.call(customer: customer) } }
      end
    end
  end
end
