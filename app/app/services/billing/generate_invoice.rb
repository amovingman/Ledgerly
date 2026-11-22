module Billing
  class GenerateInvoice
    def initialize(subscription:, period_start:)
      @subscription = subscription
      @period = Period.new(period_start)
    end

    def call
      @subscription.customer.with_lock do
        @subscription.reload
        existing = @subscription.invoices.find_by(period_start: @period.start)
        existing ? Result.new(record: existing, replayed: true) : issue
      end
    end

    private

    def issue
      @period.validate_for!(@subscription)
      quantity = unbilled_usage.sum(:quantity)
      raise Error.new('no_usage', 'This subscription has no unbilled usage in that month.') if quantity.zero?
      if quantity > Input::MAX_BIGINT || quantity * @subscription.unit_amount > Input::MAX_BIGINT
        raise Error.new('amount_out_of_range', 'The aggregate quantity or invoice amount exceeds the supported range.')
      end

      Result.new(record: persist_invoice(quantity), replayed: false)
    end

    def unbilled_usage
      @subscription.usage_events.where(invoice_line_item_id: nil, occurred_at: @period.start...@period.finish)
    end

    def persist_invoice(quantity)
      invoice = @subscription.invoices.create!(customer: @subscription.customer, period_start: @period.start,
                                               period_end: @period.finish, currency: @subscription.currency,
                                               amount: quantity * @subscription.unit_amount)
      line = invoice.invoice_line_items.create!(metric: @subscription.metric, quantity: quantity,
                                                unit_amount: @subscription.unit_amount, amount: invoice.amount)
      allocate_and_post(invoice, line)
      invoice
    end

    def allocate_and_post(invoice, line)
      # The customer lock and NULL predicate protect one-time allocation; snapshots were validated above.
      unbilled_usage.update_all(invoice_line_item_id: line.id) # rubocop:disable Rails/SkipsModelValidations
      unless line.usage_events.sum(:quantity) == line.quantity
        raise Error.new('allocation_conflict', 'Usage allocation changed during invoice generation.', status: 409)
      end

      PostIssuance.call(invoice: invoice)
    end
  end
end
