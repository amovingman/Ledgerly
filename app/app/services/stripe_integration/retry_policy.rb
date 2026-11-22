module StripeIntegration
  module RetryPolicy
    extend ActiveSupport::Concern

    included do
      sidekiq_options retry: 7, dead: true, backtrace: 5
      sidekiq_retry_in do |count, exception, _job|
        exception.is_a?(ReviewRequired) ? :kill : [(2**(count + 1)) + rand(0..3), 300].min
      end
    end

    def self.exhausted(model, job, error)
      target = model.find_by(id: job.fetch('args').first)
      return unless target && !target.terminal?

      target.update!(status: 'dead', last_error: error.respond_to?(:code) ? error.code : 'job_failed')
    end
  end
end
