module Dashboard
  class DataController < BaseController
    include ApiErrors

    before_action :require_viewer!

    def index
      render json: Query.new(params).call(params[:section])
    end

    def invoice
      render json: { data: Details.invoice(Billing::Input.identifier(params[:id])) }
    end

    def webhook
      render json: { data: Details.webhook(Billing::Input.identifier(params[:id])) }
    end

    def customer
      render json: { data: Details.customer(Billing::Input.identifier(params[:id])) }
    end
  end
end
