# typed: true

require 'digest'
require 'json'

module Billing
  class IngestUsage
    extend T::Sig

    sig { params(customer: Customer, subscription: Subscription, attributes: T::Hash[Symbol, T.untyped], idempotency_key: T.untyped).void }
    def initialize(customer:, subscription:, attributes:, idempotency_key:)
      @customer = customer
      @subscription = subscription
      @key = idempotency_key
      @payload = canonical_payload(attributes)
      @fingerprint = fingerprint
      return if @key.is_a?(String) && /\A[A-Za-z0-9._:-]{1,128}\z/.match?(@key)

      raise Error.new('invalid_idempotency_key', 'A valid Idempotency-Key header is required.')
    end

    sig { returns(Result[UsageEvent]) }
    def call
      @customer.with_lock do
        existing = @customer.usage_events.find_by(idempotency_key: @key)
        existing ? replay(existing) : create_event
      end
    end

    private

    sig { returns(String) }
    def fingerprint
      values = [@subscription.id, @payload[:metric], @payload[:quantity], @payload[:occurred_at].iso8601(6)]
      Digest::SHA256.hexdigest(JSON.generate(values))
    end

    sig { params(attributes: T::Hash[Symbol, T.untyped]).returns(Billing::Types::Usage) }
    def canonical_payload(attributes)
      { metric: Input.text(attributes[:metric], field: 'metric', maximum: 64),
        quantity: Input.positive_integer(attributes[:quantity], field: 'quantity', maximum: 1_000_000_000),
        occurred_at: Input.timestamp(attributes[:occurred_at], field: 'occurred_at') }
    end

    sig { params(event: UsageEvent).returns(Result[UsageEvent]) }
    def replay(event)
      unless event.request_fingerprint == @fingerprint
        raise Error.new('idempotency_conflict', 'This key has already been used for a different usage payload.',
                        status: 409)
      end

      Result[UsageEvent].new(record: event, replayed: true)
    end

    sig { returns(Result[UsageEvent]) }
    def create_event
      @subscription.reload
      raise ActiveRecord::RecordNotFound unless @subscription.customer_id == @customer.id

      validate_contract!
      if @subscription.invoices.exists?(period_start: @payload[:occurred_at].beginning_of_month)
        raise Error.new('usage_period_closed', 'An invoice has already closed this usage period.', status: 409)
      end

      event = @customer.usage_events.create!(**@payload, subscription: @subscription,
                                                         idempotency_key: @key, request_fingerprint: @fingerprint)
      Result[UsageEvent].new(record: event, replayed: false)
    end

    sig { void }
    def validate_contract!
      if @payload[:metric] != @subscription.metric
        raise Error.new('metric_mismatch', 'The metric must match the subscription.')
      end

      occurred = @payload[:occurred_at]
      raise Error.new('future_usage', 'Usage cannot occur in the future.') if occurred > Time.current
      return if occurred >= @subscription.starts_at && (@subscription.ends_at.nil? || occurred < @subscription.ends_at)

      raise Error.new('outside_subscription', 'Usage must occur within the subscription active interval.')
    end
  end
end
