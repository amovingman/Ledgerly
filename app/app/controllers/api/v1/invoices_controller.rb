module Api
  module V1
    class InvoicesController < BaseController
      def index
        customer = find_record(Customer, params[:customer_id])
        window = pagination
        payload = Billing::ReadCache.fetch(customer: customer, key: "invoices:#{window.page}:#{window.per_page}",
                                           cacheable: window.page <= 10) do
          summaries(customer, window)
        end
        render json: payload
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

      private

      def summaries(customer, window)
        scope = customer.invoices.order(created_at: :desc, id: :desc)
        records = scope.limit(window.per_page).offset(window.offset)
        { data: records.map { |record| Representation.invoice_summary(record) },
          meta: { page: window.page, per_page: window.per_page, total: scope.count } }
      end
    end
  end
end
