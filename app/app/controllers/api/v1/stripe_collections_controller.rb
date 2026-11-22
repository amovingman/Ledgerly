module Api
  module V1
    class StripeCollectionsController < BaseController
      def show
        invoice = find_record(Invoice, params[:invoice_id])
        collection = invoice.invoice_collection || raise(ActiveRecord::RecordNotFound)
        render json: { data: representation(collection) }
      end

      def create
        invoice = find_record(Invoice, params[:invoice_id])
        collection = StripeIntegration::RequestCollection.call(invoice: invoice)
        StripeIntegration::OutboxDispatcher.call(record_id: collection.outbox_record.id)
        render json: { data: representation(collection) }, status: :accepted
      end

      private

      def representation(collection)
        collection.slice(:id, :invoice_id, :status, :attempts, :last_error).merge(
          stripe_invoice_id: collection.invoice.stripe_invoice_id
        )
      end
    end
  end
end
