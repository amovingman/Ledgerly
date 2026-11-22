module Api
  module V1
    class InvoicesController < BaseController
      def index
        customer = find_record(Customer, params[:customer_id])
        render_collection(customer.invoices.order(created_at: :desc, id: :desc), :invoice_summary)
      end

      def show
        scope = Invoice.includes(:invoice_line_items, ledger_transactions: :ledger_entries)
        render json: { data: Representation.invoice(find_record(scope)) }
      end

      def create
        attributes = params.expect(invoice: [:period_start])
        subscription = find_record(Subscription, params[:subscription_id])
        result = Billing::GenerateInvoice.new(subscription: subscription, period_start: attributes[:period_start]).call
        render_result(result, :invoice)
      end
    end
  end
end
