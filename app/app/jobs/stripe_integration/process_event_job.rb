module StripeIntegration
  class ProcessEventJob
    include Sidekiq::Job
    include RetryPolicy

    sidekiq_options queue: 'webhooks'
    sidekiq_retries_exhausted { |job, error| RetryPolicy.exhausted(StripeEvent, job, error) }

    def perform(id)
      event = StripeEvent.find(id)
      ProcessEvent.new(event: event).call
    rescue Retryable => e
      return self.class.perform_in(rand(2..5), id) if e.code == 'operation_busy'
      raise ReviewRequired, e.code if event.reload.status == 'dead'

      raise
    end
  end
end
