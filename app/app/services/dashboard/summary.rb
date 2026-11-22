module Dashboard
  module Summary
    def self.call
      ApplicationRecord.uncached do
        return { data: snapshot } if ApplicationRecord.connection.transaction_open?

        read_snapshot
      end
    end

    def self.read_snapshot
      ApplicationRecord.transaction(isolation: :repeatable_read) do
        ApplicationRecord.connection.execute('SET TRANSACTION READ ONLY')
        { data: snapshot }
      end
    end

    def self.snapshot
      { counts: counts,
        invoice_states: Invoice.group(:status).count, webhook_states: StripeEvent.group(:status).count,
        ledger_totals: ledger_totals, usage_metrics: usage_metrics,
        recent_ledger: Collections.scope('ledger').limit(6).map { |record| Presentation.ledger(record) },
        updated_at: Time.current.iso8601(6) }.merge(recent)
    end

    def self.counts
      { customers: Customer.count, usage: UsageEvent.count, invoices: Invoice.count,
        ledger: LedgerEntry.count, webhooks: StripeEvent.count }
    end

    def self.recent
      %w[customers invoices webhooks usage].to_h do |section|
        records = Collections.scope(section).reorder(id: :desc).limit(3)
        ["recent_#{section}", records.map { |record| Presentation.public_send(section, record) }]
      end
    end

    def self.ledger_totals
      LedgerEntry.joins(:ledger_transaction).group('ledger_transactions.currency')
                 .pluck(Arel.sql('ledger_transactions.currency'), Arel.sql('SUM(debit)'), Arel.sql('SUM(credit)'))
                 .sort.map do |currency, debit, credit|
        { currency: currency, debit: debit.to_i.to_s,
          credit: credit.to_i.to_s }
      end
    end

    def self.usage_metrics
      UsageEvent.group(:metric).order(:metric).limit(20).sum(:quantity)
                .map { |metric, quantity| { metric: metric, quantity: quantity.to_s } }
    end
  end
end
