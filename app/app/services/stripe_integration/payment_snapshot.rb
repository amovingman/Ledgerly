module StripeIntegration
  class PaymentSnapshot
    def initialize(gateway:)
      @gateway = gateway
    end

    def call(invoice:, remote:, allocation:)
      validate_allocation!(invoice, remote, allocation)
      intent = @gateway.retrieve('payment_intent', allocation.fetch('payment').fetch('payment_intent'))
      charge = @gateway.retrieve('charge', intent.fetch('latest_charge'))
      validate_payment!(invoice, remote, intent, charge)
      refunds = settled_refunds(charge)
      validate_refunds!(invoice, charge, refunds)
      { allocation: allocation, intent: intent, charge: charge, refunds: refunds }
    end

    private

    def settled_refunds(charge)
      refunds = @gateway.list('refund', charge: charge.fetch('id'))
      if refunds.any? { |refund| %w[pending requires_action].include?(refund['status']) }
        raise Retryable, 'refund_pending'
      end

      refunds.select { |refund| refund['status'] == 'succeeded' }
    end

    def validate_allocation!(invoice, remote, allocation)
      Contract.check!(allocation, { livemode: false, amount_paid: invoice.amount, currency: invoice.currency.downcase,
                                    invoice: remote.fetch('id') }, code: 'unsupported_invoice_payment')
      Contract.check!(allocation.fetch('payment'), { type: 'payment_intent' }, code: 'unsupported_invoice_payment')
    end

    def validate_payment!(invoice, remote, intent, charge)
      common = { livemode: false, currency: invoice.currency.downcase, customer: invoice.customer.stripe_customer_id }
      code = 'payment_amount_or_identity_mismatch'
      Contract.check!(intent, common.merge(status: 'succeeded', amount_received: invoice.amount), code: code)
      Contract.check!(charge, common.merge(payment_intent: intent.fetch('id'), paid: true, captured: true,
                                           amount_captured: invoice.amount), code: code)
      Contract.check!(remote, { amount_paid: invoice.amount }, code: code)
    end

    def validate_refunds!(invoice, charge, refunds)
      refunds.each { |refund| validate_refund!(invoice, charge, refund) }
      ids = refunds.pluck('id')
      return if ids.uniq.size == ids.size && refunds.sum { |refund| refund.fetch('amount') } <= invoice.amount

      raise ReviewRequired, 'invalid_refund_total_or_identity'
    end

    def validate_refund!(invoice, charge, refund)
      amount = refund['amount']
      raise ReviewRequired, 'invalid_refund_total_or_identity' unless amount.is_a?(Integer) && amount.positive?

      Contract.check!(refund, { currency: invoice.currency.downcase, charge: charge.fetch('id') },
                      code: 'invalid_refund_total_or_identity')
    end
  end
end
