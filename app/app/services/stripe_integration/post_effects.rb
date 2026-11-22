module StripeIntegration
  class PostEffects
    def initialize(event:, snapshot:)
      @event = event
      @snapshot = snapshot
      @invoice = snapshot.fetch(:invoice)
    end

    def call
      @invoice.customer.with_lock do
        @event.reload
        return if @event.terminal?

        @invoice.reload
        @invoice.update!(stripe_invoice_id: @snapshot.fetch(:remote).fetch('id'))
        apply_payment_snapshot
        update_status
        @event.update!(status: 'processed', processed_at: Time.current, last_error: nil)
      end
    end

    private

    def apply_payment_snapshot
      return unless @snapshot[:payment]

      payment = post_payment(@snapshot.fetch(:payment))
      @snapshot.fetch(:payment).fetch(:refunds).each { |refund| post_refund(payment, refund) }
    end

    def payment_identity(snapshot)
      { invoice_id: @invoice.id, charge_id: snapshot.fetch(:charge).fetch('id'),
        payment_intent_id: snapshot.fetch(:intent).fetch('id'),
        invoice_payment_id: snapshot.fetch(:allocation).fetch('id'), amount: @invoice.amount,
        currency: @invoice.currency }
    end

    def post_payment(snapshot)
      identity = payment_identity(snapshot)
      existing = StripePayment.find_by(charge_id: identity.fetch(:charge_id)) || @invoice.stripe_payment
      return verify_existing(existing, identity) if existing
      if StripePayment.exists?(payment_intent_id: identity.fetch(:payment_intent_id))
        raise ReviewRequired, 'shared_payment_unsupported'
      end

      journal = post_journal('payment', "stripe:payment:#{identity.fetch(:charge_id)}", @invoice.amount,
                             'stripe_clearing', 'accounts_receivable')
      StripePayment.create!(**identity, ledger_transaction: journal)
    end

    def refund_identity(payment, remote)
      { stripe_payment_id: payment.id, stripe_id: remote.fetch('id'), amount: remote.fetch('amount'),
        currency: @invoice.currency }
    end

    def post_refund(payment, remote)
      identity = refund_identity(payment, remote)
      existing = StripeRefund.find_by(stripe_id: remote.fetch('id'))
      return verify_existing(existing, identity) if existing
      if payment.stripe_refunds.sum(:amount) + identity.fetch(:amount) > payment.amount
        raise ReviewRequired, 'refund_exceeds_payment'
      end

      journal = post_journal('refund', "stripe:refund:#{remote.fetch('id')}", remote.fetch('amount'),
                             'sales_returns', 'stripe_clearing')
      StripeRefund.create!(**identity, ledger_transaction: journal)
    end

    def verify_existing(record, identity)
      unless identity.all? { |key, value| record.public_send(key) == value }
        raise ReviewRequired, 'financial_effect_identity_mismatch'
      end

      record
    end

    def post_journal(kind, key, amount, debit_account, credit_account)
      @invoice.ledger_transactions.create!(journal_type: kind, business_effect_key: key, currency: @invoice.currency,
                                           stripe_event: @event,
                                           ledger_entries: [LedgerEntry.new(account: debit_account, debit: amount),
                                                            LedgerEntry.new(account: credit_account, credit: amount)])
    end

    def update_status
      payment = @invoice.reload.stripe_payment
      if payment
        status = payment.stripe_refunds.sum(:amount) == payment.amount ? 'refunded' : 'paid'
        @invoice.update!(status: status)
      elsif @event.event_type == 'invoice.payment_failed'
        @invoice.update!(status: 'payment_failed')
      end
    end
  end
end
