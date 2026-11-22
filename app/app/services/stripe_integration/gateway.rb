module StripeIntegration
  class Gateway
    SERVICES = { 'customer' => :customers, 'invoice' => :invoices, 'item' => :invoice_items,
                 'invoice_payment' => :invoice_payments, 'payment_intent' => :payment_intents,
                 'charge' => :charges, 'refund' => :refunds }.freeze

    def initialize
      configuration = [Settings.secret_key!, client_options]
      slot = Thread.current[:ledgerly_stripe_client]
      unless slot && slot.first == configuration
        slot = [configuration, Stripe::StripeClient.new(configuration.first, **configuration.last)]
        Thread.current[:ledgerly_stripe_client] = slot
      end
      @client = slot.last
    rescue Billing::Error
      raise Retryable, 'stripe_unavailable', cause: nil
    end

    def retrieve(kind, id)
      api { normalize(service(kind).retrieve(id)) }
    end

    def list(kind, parameters = {})
      api { service(kind).list(parameters.merge(limit: 100)).auto_paging_each.map { |item| normalize(item) } }
    end

    def create(operation)
      api { normalize(service(operation.kind).create(operation.payload, idempotency_key: operation.idempotency_key)) }
    end

    def finalize(operation)
      api do
        normalize(@client.v1.invoices.finalize_invoice(operation.invoice.stripe_invoice_id, operation.payload,
                                                       idempotency_key: operation.idempotency_key))
      end
    end

    private

    # The SDK retains persistent connections by client configuration. Reusing
    # one client per worker thread keeps that pool bounded across jobs.
    def client_options
      { stripe_version: Settings::API_VERSION }
    end

    def service(kind)
      name = SERVICES.fetch(kind.to_s) { raise ReviewRequired, 'unsupported_resource' }
      @client.v1.public_send(name)
    end

    def normalize(value)
      JSON.parse(value.to_json)
    end

    def api
      yield
    rescue Stripe::APIConnectionError, Stripe::APIError, Stripe::RateLimitError
      raise Retryable, 'stripe_unavailable', cause: nil
    rescue Stripe::StripeError
      raise ReviewRequired, 'stripe_request_rejected', cause: nil
    end
  end
end
