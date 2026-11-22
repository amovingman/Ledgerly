module StripeIntegration
  module ReceiveEvent
    def self.call(raw:, signature:)
      reject!('payload_too_large', 413) if raw.bytesize > 1_048_576
      Stripe::Webhook.construct_event(raw, signature, Settings.webhook_secret!, tolerance: 300)
      payload = JSON.parse(raw)
      validate!(payload)
      persist(raw, payload)
    rescue Stripe::SignatureVerificationError, JSON::ParserError, ArgumentError, TypeError, NoMethodError
      reject!('invalid_webhook')
    end

    def self.validate!(payload)
      reject!('invalid_webhook') unless valid_envelope?(payload)
      reject!('live_event_rejected') unless payload['livemode'] == false
      reject!('connect_event_rejected') if payload['account'] || payload['context']
      reject!('webhook_version_mismatch') unless payload['api_version'] == Settings::API_VERSION
    end

    def self.valid_envelope?(payload)
      payload.is_a?(Hash) && valid_id?(payload['id']) && valid_type?(payload['type']) &&
        payload.dig('data', 'object').is_a?(Hash)
    end

    def self.valid_id?(value)
      value.is_a?(String) && /\Aevt_[A-Za-z0-9_]{1,240}\z/.match?(value)
    end

    def self.valid_type?(value)
      value.is_a?(String) && value.length.between?(1, 200)
    end

    def self.reject!(code, status = 400)
      raise Billing::Error.new(code, 'The webhook signature, source, version or payload is unsupported.',
                               status: status)
    end

    def self.persist(raw, payload)
      Billing::Result.new(record: store(raw, payload), replayed: false)
    rescue ActiveRecord::RecordNotUnique
      event = StripeEvent.find_by!(stripe_id: payload.fetch('id'))
      unless event.payload == payload
        raise Billing::Error.new('event_payload_conflict', 'This event ID already has a different payload.',
                                 status: 409)
      end

      Billing::Result.new(record: event, replayed: true)
    end

    def self.store(raw, payload)
      StripeEvent.transaction do
        event = StripeEvent.create!(stripe_id: payload.fetch('id'), event_type: payload.fetch('type'),
                                    api_version: payload.fetch('api_version'), payload: payload, raw_payload: raw)
        OutboxRecord.create!(stripe_event: event, available_at: Time.current)
        event
      end
    end
    private_class_method :validate!, :valid_envelope?, :valid_id?, :valid_type?, :reject!, :persist, :store
  end
end
