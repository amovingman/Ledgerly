module Dashboard
  module Collections
    STATUSES = { 'invoices' => %w[issued paid payment_failed refunded],
                 'webhooks' => %w[received processed ignored dead review], 'usage' => %w[billed unbilled] }.freeze
    SEARCH = {
      'customers' => 'customers.name ILIKE :query OR customers.email ILIKE :query',
      'usage' => 'usage_events.metric ILIKE :query OR customers.name ILIKE :query',
      'invoices' => 'CAST(invoices.id AS TEXT) ILIKE :query OR customers.name ILIKE :query',
      'ledger' => 'ledger_entries.account ILIKE :query OR ledger_transactions.business_effect_key ILIKE :query',
      'webhooks' => 'stripe_events.stripe_id ILIKE :query OR stripe_events.event_type ILIKE :query'
    }.freeze

    def self.scope(section)
      case section
      when 'customers' then Customer.order(id: :desc)
      when 'usage' then UsageEvent.joins(:customer).includes(:customer, :invoice_line_item).order(occurred_at: :desc,
                                                                                                  id: :desc)
      when 'invoices' then Invoice.joins(:customer).includes(:customer).order(created_at: :desc, id: :desc)
      when 'ledger'
        LedgerEntry.joins(ledger_transaction: :invoice).includes(ledger_transaction: :invoice).order(id: :desc)
      when 'webhooks' then StripeEvent.includes(:outbox_record).order(created_at: :desc, id: :desc)
      end
    end
  end
end
