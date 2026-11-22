require 'digest'
require_relative 'fixture'

module LedgerlyBenchmark
  module Verify
    COUNTS = { customers: 1000, plans: 80, subscriptions: 1460, invoices: 50_000,
               invoice_line_items: 50_000, usage_events: 150_000 }.freeze
    CHECKS = {
      invoice_totals: <<~SQL.squish,
        SELECT i.id FROM invoices i LEFT JOIN invoice_line_items l ON l.invoice_id=i.id
        GROUP BY i.id HAVING COALESCE(sum(l.amount),0)<>i.amount
      SQL
      usage_allocations: <<~SQL.squish,
        SELECT l.id FROM invoice_line_items l LEFT JOIN usage_events u ON u.invoice_line_item_id=l.id
        JOIN invoices i ON i.id=l.invoice_id GROUP BY l.id,i.id
        HAVING COALESCE(sum(u.quantity),0)<>l.quantity OR count(u.id)<>3
          OR bool_or(u.customer_id<>i.customer_id OR u.subscription_id<>i.subscription_id OR u.metric<>l.metric
          OR u.occurred_at<i.period_start OR u.occurred_at>=i.period_end)
      SQL
      journal_balance: <<~SQL.squish,
        SELECT j.id FROM ledger_transactions j LEFT JOIN ledger_entries e ON e.ledger_transaction_id=j.id
        JOIN invoices i ON i.id=j.invoice_id GROUP BY j.id,i.id
        HAVING count(e.id)<>2 OR sum(e.debit)<>sum(e.credit) OR j.currency<>i.currency
      SQL
      payment_identity: <<~SQL.squish,
        SELECT p.id FROM stripe_payments p JOIN invoices i ON i.id=p.invoice_id
        JOIN ledger_transactions j ON j.id=p.ledger_transaction_id
        WHERE p.amount<>i.amount OR p.currency<>i.currency OR j.invoice_id<>i.id OR j.journal_type<>'payment'
          OR j.business_effect_key<>'stripe:payment:'||p.charge_id
          OR (SELECT sum(debit) FROM ledger_entries WHERE ledger_transaction_id=j.id)<>p.amount
      SQL
      refund_totals: <<~SQL.squish,
        SELECT p.id FROM stripe_payments p JOIN stripe_refunds r ON r.stripe_payment_id=p.id
        GROUP BY p.id HAVING sum(r.amount)>p.amount OR bool_or(r.currency<>p.currency)
      SQL
      invoice_states: <<~SQL.squish,
        SELECT i.id FROM invoices i LEFT JOIN stripe_payments p ON p.invoice_id=i.id
        LEFT JOIN stripe_refunds r ON r.stripe_payment_id=p.id GROUP BY i.id,p.id
        HAVING (i.status IN ('paid','refunded'))<>(p.id IS NOT NULL)
          OR (i.status='refunded' AND COALESCE(sum(r.amount),0)<>p.amount)
          OR (i.status='paid' AND COALESCE(sum(r.amount),0)>=p.amount)
      SQL
      issuance_identity: <<~SQL.squish,
        SELECT i.id FROM invoices i LEFT JOIN ledger_transactions j ON j.invoice_id=i.id AND j.journal_type='issuance'
        GROUP BY i.id HAVING count(j.id)<>1 OR max(j.business_effect_key)<>'invoice:'||i.id||':issuance'
          OR max((SELECT sum(debit) FROM ledger_entries WHERE ledger_transaction_id=j.id))<>i.amount
      SQL
      refund_identity: <<~SQL.squish
        SELECT r.id FROM stripe_refunds r JOIN stripe_payments p ON p.id=r.stripe_payment_id
        JOIN ledger_transactions j ON j.id=r.ledger_transaction_id
        WHERE j.invoice_id<>p.invoice_id OR j.journal_type<>'refund'
          OR j.business_effect_key<>'stripe:refund:'||r.stripe_id
          OR (SELECT sum(debit) FROM ledger_entries WHERE ledger_transaction_id=j.id)<>r.amount
      SQL
    }.freeze

    def self.call(fingerprint: false)
      # Long-running replay threads commit on other connections. Never reuse
      # the observer's earlier SQL results when checking their final effects.
      ActiveRecord::Base.uncached { snapshot(fingerprint: fingerprint) }
    end

    def self.snapshot(fingerprint:)
      connection = ActiveRecord::Base.connection
      counts = COUNTS.keys.index_with { |table| connection.select_value("SELECT count(*) FROM #{table}") }
      raise 'Unexpected fixture counts' unless counts == COUNTS

      violations = CHECKS.transform_values { |sql| connection.select_value("SELECT count(*) FROM (#{sql}) invalid") }
      raise "Accounting violations: #{violations}" unless violations.values.all?(&:zero?)

      verify_samples!
      result = { fixture_version: 'v1', seed: 20_261_121, counts: counts, violations: violations,
                 financial_counts: financial_counts(connection), invoice_statuses: Invoice.group(:status).count,
                 database_bytes: connection.select_value('SELECT pg_database_size(current_database())') }
      result[:table_fingerprints] = fingerprints(connection) if fingerprint
      result
    end
    private_class_method :snapshot

    def self.verify_samples!
      ids = [1, 10_000, 10_001, 28_000, 28_001, 38_000, 38_001, 50_000]
      ids.each do |id|
        invoice = Invoice.find(id)
        line = invoice.invoice_line_items.first
        expected = Fixture.attributes(id)
        actual = [invoice.customer_id, invoice.subscription_id, invoice.amount, line.quantity, line.unit_amount]
        fields = %i[customer_id subscription_id amount quantity unit_amount]
        raise 'SQL/provider fixture mismatch' unless actual == fields.map { |field| expected.fetch(field) }

        usage = line.usage_events.first
        values = [usage.subscription_id, usage.metric, usage.quantity, usage.occurred_at.iso8601(6)]
        unless usage.request_fingerprint == Digest::SHA256.hexdigest(JSON.generate(values))
          raise 'Invalid usage fingerprint'
        end
      end
    end

    def self.financial_counts(connection)
      %w[stripe_payments stripe_refunds ledger_transactions ledger_entries stripe_events
         outbox_records].index_with do |table|
        connection.select_value("SELECT count(*) FROM #{table}")
      end
    end

    def self.fingerprints(connection)
      %w[customers plans subscriptions invoices invoice_line_items usage_events stripe_events
         ledger_transactions ledger_entries stripe_payments stripe_refunds].to_h do |table|
        # SQL hashes each ordered row; the small ordered array of row hashes feeds SHA-256.
        columns = connection.columns(table).map(&:name) - ['read_version']
        projection = columns.map { |name| connection.quote_column_name(name) }.join(', ')
        rows = connection.select_values(<<~SQL.squish)
          SELECT md5(row_to_json(t)::text) FROM (SELECT #{projection} FROM #{table}) t ORDER BY id
        SQL
        [table, Digest::SHA256.hexdigest(rows.join)]
      end
    end
  end
end
