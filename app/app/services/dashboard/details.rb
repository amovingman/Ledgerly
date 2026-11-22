module Dashboard
  module Details
    def self.customer(id)
      record = Customer.find(id)
      Presentation.customers(record).merge(
        invoice_count: record.invoices.count, usage_count: record.usage_events.count,
        balances: Billing::CustomerBalance.call(customer: record).map do |balance|
          balance.merge(amount: balance.fetch(:amount).to_s)
        end
      )
    end

    def self.invoice(id)
      record = Invoice.includes(:customer).find(id)
      Presentation.invoices(record).merge(line_items: line_items(record),
                                          line_item_count: record.invoice_line_items.count,
                                          journal_count: record.ledger_transactions.count)
    end

    def self.webhook(id)
      Presentation.webhooks(StripeEvent.includes(:outbox_record).find(id))
    end

    def self.line_items(record)
      record.invoice_line_items.order(:id).limit(100).map do |line|
        { metric: line.metric, quantity: line.quantity.to_s, unit_amount: line.unit_amount.to_s,
          amount: line.amount.to_s }
      end
    end
  end
end
