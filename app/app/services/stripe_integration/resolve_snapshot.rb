# typed: true

module StripeIntegration
  class ResolveSnapshot
    extend T::Sig

    SUPPORTED = %w[invoice.paid invoice.payment_failed charge.refunded].freeze

    sig { params(gateway: T.untyped).void }
    def initialize(gateway:)
      @gateway = gateway
    end

    sig { params(event: StripeEvent).returns(StripeIntegration::Types::Snapshot) }
    def call(event)
      object = event.payload.fetch('data').fetch('object')
      remote_id = event.event_type == 'charge.refunded' ? invoice_for_charge(object.fetch('id')) : object.fetch('id')
      remote = @gateway.retrieve('invoice', remote_id)
      invoice = local_invoice(remote)
      validate_invoice!(invoice, remote)
      if event.event_type != 'invoice.payment_failed' && remote['status'] != 'paid'
        raise Retryable, 'payment_not_visible'
      end

      payment = payment_snapshot(invoice, remote)
      { invoice: invoice, remote: remote, payment: payment }
    end

    private

    sig { params(id: String).returns(String) }
    def invoice_for_charge(id)
      charge = @gateway.retrieve('charge', id)
      intent = charge.fetch('payment_intent')
      matches = @gateway.list('invoice_payment', payment: { type: 'payment_intent', payment_intent: intent })
                        .select { |payment| payment['status'] == 'paid' }
      raise Retryable, 'unmapped_charge' if matches.empty?
      raise ReviewRequired, 'shared_payment_unsupported' unless matches.one?

      matches.first.fetch('invoice')
    end

    sig { params(remote: StripeIntegration::Types::JsonObject).returns(Invoice) }
    def local_invoice(remote)
      invoice = Invoice.find_by(stripe_invoice_id: remote.fetch('id'))
      return invoice if invoice

      operation = StripeOperation.find_by(kind: 'invoice', invoice_id: remote.dig('metadata', 'ledgerly_invoice_id'),
                                          idempotency_key: remote.dig('metadata', 'ledgerly_operation'))
      raise Retryable, 'unmapped_invoice' unless operation

      T.must(operation.invoice)
    end

    sig { params(invoice: Invoice, remote: StripeIntegration::Types::JsonObject).void }
    def validate_invoice!(invoice, remote)
      Contract.check!(remote, { livemode: false, customer: T.must(invoice.customer).stripe_customer_id,
                                currency: invoice.currency.downcase, total: invoice.amount },
                      code: 'remote_invoice_mismatch')
      return unless invoice.stripe_invoice_id && invoice.stripe_invoice_id != remote.fetch('id')

      raise ReviewRequired, 'invoice_mapping_conflict'
    end

    sig { params(invoice: Invoice, remote: StripeIntegration::Types::JsonObject).returns(T.nilable(StripeIntegration::Types::Payment)) }
    def payment_snapshot(invoice, remote)
      payments = @gateway.list('invoice_payment', invoice: remote.fetch('id')).select do |item|
        item['status'] == 'paid'
      end
      return nil if payments.empty? && remote['status'] != 'paid'
      raise Retryable, 'payment_not_visible' if payments.empty?
      raise ReviewRequired, 'partial_or_shared_payment_unsupported' unless payments.one?

      PaymentSnapshot.new(gateway: @gateway).call(invoice: invoice, remote: remote, allocation: payments.first)
    end
  end
end
