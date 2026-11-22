# typed: true

module StripeIntegration
  class PostEffects
    extend T::Sig

    sig { params(event: StripeEvent, snapshot: StripeIntegration::Types::Snapshot).void }
    def initialize(event:, snapshot:)
      @event = event
      @snapshot = snapshot
      @invoice = snapshot[:invoice]
    end

    sig { void }
    def call
      T.must(@invoice.customer).with_lock do
        @event.reload
        return if @event.terminal?

        @invoice.reload
        @invoice.update!(stripe_invoice_id: @snapshot[:remote].fetch('id'))
        apply_payment_snapshot
        update_status
        @event.update!(status: 'processed', processed_at: Time.current, last_error: nil)
      end
    end

    private

    sig { void }
    def apply_payment_snapshot
      snapshot = @snapshot[:payment]
      return unless snapshot

      payment = post_payment(snapshot)
      snapshot[:refunds].each { |refund| post_refund(payment, refund) }
    end

    sig { params(snapshot: StripeIntegration::Types::Payment).returns(T::Hash[Symbol, T.untyped]) }
    def payment_identity(snapshot)
      { invoice_id: @invoice.id, charge_id: snapshot[:charge].fetch('id'),
        payment_intent_id: snapshot[:intent].fetch('id'),
        invoice_payment_id: snapshot[:allocation].fetch('id'), amount: @invoice.amount,
        currency: @invoice.currency }
    end

    sig { params(snapshot: StripeIntegration::Types::Payment).returns(StripePayment) }
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

    sig { params(payment: StripePayment, remote: StripeIntegration::Types::JsonObject).returns(T::Hash[Symbol, T.untyped]) }
    def refund_identity(payment, remote)
      { stripe_payment_id: payment.id, stripe_id: remote.fetch('id'), amount: remote.fetch('amount'),
        currency: @invoice.currency }
    end

    sig { params(payment: StripePayment, remote: StripeIntegration::Types::JsonObject).returns(StripeRefund) }
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

    sig { type_parameters(:Record).params(record: T.all(T.type_parameter(:Record), ApplicationRecord), identity: T::Hash[Symbol, T.untyped]).returns(T.type_parameter(:Record)) }
    def verify_existing(record, identity)
      unless identity.all? { |key, value| record.public_send(key) == value }
        raise ReviewRequired, 'financial_effect_identity_mismatch'
      end

      record
    end

    sig do
      params(kind: String, key: String, amount: Integer, debit_account: String,
             credit_account: String).returns(LedgerTransaction)
    end
    def post_journal(kind, key, amount, debit_account, credit_account)
      @invoice.ledger_transactions.create!(journal_type: kind, business_effect_key: key, currency: @invoice.currency,
                                           stripe_event: @event,
                                           ledger_entries: [LedgerEntry.new(account: debit_account, debit: amount),
                                                            LedgerEntry.new(account: credit_account, credit: amount)])
    end

    sig { void }
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
