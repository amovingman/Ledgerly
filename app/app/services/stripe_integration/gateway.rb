# typed: true

module StripeIntegration
  class Gateway
    extend T::Sig

    SERVICES = { 'customer' => :customers, 'invoice' => :invoices, 'item' => :invoice_items,
                 'invoice_payment' => :invoice_payments, 'payment_intent' => :payment_intents,
                 'charge' => :charges, 'refund' => :refunds }.freeze

    sig { void }
    def initialize
      configuration = [Settings.secret_key!, client_options]
      slot = Thread.current[:ledgerly_stripe_client]
      unless slot && slot.first == configuration
        slot = [configuration, Stripe::StripeClient.new(configuration.first, **configuration.last)]
        Thread.current[:ledgerly_stripe_client] = slot
      end
      @client = slot.last
    rescue Billing::Error
      raise Retryable.new('stripe_unavailable'), cause: nil
    end

    sig { params(kind: String, id: String).returns(Types::JsonObject) }
    def retrieve(kind, id)
      api { normalize(service(kind).retrieve(id)) }
    end

    sig { params(kind: String, parameters: Types::Parameters).returns(T::Array[Types::JsonObject]) }
    def list(kind, parameters = {})
      api { service(kind).list(parameters.merge(limit: 100)).auto_paging_each.map { |item| normalize(item) } }
    end

    sig { params(operation: StripeOperation).returns(Types::JsonObject) }
    def create(operation)
      api { normalize(service(operation.kind).create(operation.payload, idempotency_key: operation.idempotency_key)) }
    end

    sig { params(operation: StripeOperation).returns(Types::JsonObject) }
    def finalize(operation)
      api do
        normalize(@client.v1.invoices.finalize_invoice(T.must(operation.invoice).stripe_invoice_id, operation.payload,
                                                       idempotency_key: operation.idempotency_key))
      end
    end

    private

    # The SDK retains persistent connections by client configuration. Reusing
    # one client per worker thread keeps that pool bounded across jobs.
    sig { returns(T::Hash[Symbol, String]) }
    def client_options
      { stripe_version: Settings::API_VERSION }
    end

    sig { params(kind: String).returns(T.untyped) }
    def service(kind)
      name = SERVICES.fetch(kind.to_s) { raise ReviewRequired, 'unsupported_resource' }
      @client.v1.public_send(name)
    end

    sig { params(value: T.untyped).returns(Types::JsonObject) }
    def normalize(value)
      JSON.parse(value.to_json)
    end

    sig do
      type_parameters(:Value).params(block: T.proc.returns(T.type_parameter(:Value))).returns(T.type_parameter(:Value))
    end
    def api(&block)
      block.call
    rescue Stripe::APIConnectionError, Stripe::APIError, Stripe::RateLimitError
      raise Retryable.new('stripe_unavailable'), cause: nil
    rescue Stripe::StripeError
      raise ReviewRequired.new('stripe_request_rejected'), cause: nil
    end
  end
end
