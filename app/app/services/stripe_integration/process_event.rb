# typed: true

module StripeIntegration
  class ProcessEvent
    extend T::Sig

    sig { params(event: StripeEvent, gateway: T.untyped).void }
    def initialize(event:, gateway: nil)
      @event = event
      @gateway = gateway
    end

    sig { void }
    def call
      AdvisoryLock.with("event:#{@event.id}") { process_claim }
    rescue Failure => e
      fail_event(e)
      raise
    rescue KeyError, TypeError
      error = ReviewRequired.new('invalid_provider_snapshot')
      fail_event(error)
      raise error, cause: nil
    end

    private

    sig { void }
    def process_claim
      @event.reload
      return if @event.terminal?

      @event.update!(attempts: @event.attempts + 1, last_attempted_at: Time.current)
      if ResolveSnapshot::SUPPORTED.include?(@event.event_type)
        snapshot = ResolveSnapshot.new(gateway: @gateway || Gateway.new).call(@event)
        PostEffects.new(event: @event, snapshot: snapshot).call
      else
        @event.update!(status: 'ignored', processed_at: Time.current, last_error: nil)
      end
    end

    sig { params(error: Failure).void }
    def fail_event(error)
      return if error.code == 'operation_busy'

      status = error.is_a?(ReviewRequired) ? 'review' : 'received'
      status = 'dead' if @event.attempts >= Settings::MAX_ATTEMPTS && status == 'received'
      @event.update!(status: status, last_error: error.code)
    end
  end
end
