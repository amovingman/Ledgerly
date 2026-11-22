module StripeIntegration
  class CollectInvoiceJob
    include Sidekiq::Job
    include RetryPolicy

    sidekiq_options queue: 'billing'
    sidekiq_retries_exhausted { |job, error| RetryPolicy.exhausted(InvoiceCollection, job, error) }

    def perform(id)
      collection = InvoiceCollection.find(id)
      CollectInvoice.new(collection: collection).call
    rescue Retryable => e
      return self.class.perform_in(rand(2..5), id) if e.code == 'operation_busy'
      raise ReviewRequired, e.code if collection.reload.status == 'dead'

      raise
    end
  end
end
