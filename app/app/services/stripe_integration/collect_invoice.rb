# typed: true

module StripeIntegration
  class CollectInvoice
    extend T::Sig

    sig { params(collection: InvoiceCollection, gateway: T.untyped).void }
    def initialize(collection:, gateway: nil)
      @collection = collection
      @invoice = collection.invoice
      @gateway = gateway
    end

    sig { void }
    def call
      AdvisoryLock.with("customer:#{@invoice.customer_id}") { collect_claim }
    rescue Failure => e
      fail_collection(e)
      raise
    rescue KeyError, TypeError
      error = ReviewRequired.new('invalid_provider_snapshot')
      fail_collection(error)
      raise error, cause: nil
    end

    private

    sig { void }
    def collect_claim
      @collection.reload
      return if @collection.terminal?

      @collection.update!(attempts: @collection.attempts + 1, last_attempted_at: Time.current)
      collect
      @collection.update!(status: 'succeeded', completed_at: Time.current, last_error: nil)
    end

    sig { void }
    def collect
      @gateway ||= Gateway.new
      @operations = Operations.new(gateway: @gateway)
      ensure_customer
      ensure_invoice
      @invoice.invoice_line_items.order(:id).each { |line| ensure_item(line) }
      validate_invoice!(@gateway.retrieve('invoice', @invoice.stripe_invoice_id))
      operation = @operations.prepare(key: "invoice:#{@invoice.id}:finalize", kind: 'finalize',
                                      customer: @invoice.customer, invoice: @invoice, payload: { auto_advance: true })
      validate_invoice!(@operations.execute(operation))
    end

    sig { void }
    def ensure_customer
      customer = @invoice.customer
      return if customer.stripe_customer_id.present?

      operation = @operations.prepare(key: "customer:#{customer.id}", kind: 'customer', customer: customer,
                                      payload: { name: customer.name, email: customer.email,
                                                 metadata: { ledgerly_customer_id: customer.id.to_s } })
      remote = @operations.execute(operation)
      customer.update!(stripe_customer_id: remote.fetch('id'))
    end

    sig { void }
    def ensure_invoice
      operation = @operations.prepare(key: "invoice:#{@invoice.id}", kind: 'invoice', customer: @invoice.customer,
                                      invoice: @invoice, payload: invoice_payload)
      remote = @operations.execute(operation)
      if @invoice.stripe_invoice_id && @invoice.stripe_invoice_id != remote.fetch('id')
        raise ReviewRequired, 'invoice_mapping_conflict'
      end

      @invoice.customer.with_lock { @invoice.update!(stripe_invoice_id: remote.fetch('id')) }
    end

    sig { returns(StripeIntegration::Types::Parameters) }
    def invoice_payload
      { customer: @invoice.customer.stripe_customer_id, currency: @invoice.currency.downcase, auto_advance: false,
        collection_method: 'charge_automatically', pending_invoice_items_behavior: 'exclude',
        automatic_tax: { enabled: false }, discounts: [], payment_settings: { payment_method_types: ['card'] },
        metadata: { ledgerly_invoice_id: @invoice.id.to_s } }
    end

    sig { params(line: InvoiceLineItem).void }
    def ensure_item(line)
      operation = @operations.prepare(key: "invoice:#{@invoice.id}:item:#{line.id}", kind: 'item',
                                      customer: @invoice.customer, invoice: @invoice, line: line,
                                      payload: { customer: @invoice.customer.stripe_customer_id,
                                                 invoice: @invoice.stripe_invoice_id, amount: line.amount,
                                                 currency: @invoice.currency.downcase, discountable: false,
                                                 description: "#{line.metric}: #{line.quantity} units",
                                                 metadata: { ledgerly_line_id: line.id.to_s } })
      @operations.execute(operation)
    end

    sig { params(remote: StripeIntegration::Types::JsonObject).void }
    def validate_invoice!(remote)
      Contract.check!(remote, { livemode: false, total: @invoice.amount, currency: @invoice.currency.downcase,
                                customer: @invoice.customer.stripe_customer_id }, code: 'remote_invoice_mismatch')
    end

    sig { params(error: Failure).void }
    def fail_collection(error)
      return if error.code == 'operation_busy'

      status = error.is_a?(ReviewRequired) ? 'review' : 'pending'
      status = 'dead' if @collection.attempts >= Settings::MAX_ATTEMPTS && status == 'pending'
      @collection.update!(status: status, last_error: error.code)
    end
  end
end
