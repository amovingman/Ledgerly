# typed: true

module Billing
  module Audit
    extend T::Sig

    CHECKS = {
      invoice_totals: <<~SQL.squish,
        SELECT i.id FROM invoices i LEFT JOIN invoice_line_items l ON l.invoice_id=i.id
        GROUP BY i.id HAVING COALESCE(sum(l.amount),0)<>i.amount
      SQL
      usage_allocations: <<~SQL.squish,
        SELECT l.id FROM invoice_line_items l LEFT JOIN usage_events u ON u.invoice_line_item_id=l.id
        JOIN invoices i ON i.id=l.invoice_id GROUP BY l.id,i.id
        HAVING COALESCE(sum(u.quantity),0)<>l.quantity
          OR bool_or(u.customer_id<>i.customer_id OR u.subscription_id<>i.subscription_id OR u.metric<>l.metric
          OR u.occurred_at<i.period_start OR u.occurred_at>=i.period_end)
      SQL
      journal_balance: <<~SQL.squish,
        SELECT j.id FROM ledger_transactions j LEFT JOIN ledger_entries e ON e.ledger_transaction_id=j.id
        JOIN invoices i ON i.id=j.invoice_id GROUP BY j.id,i.id
        HAVING count(e.id)<2 OR sum(e.debit)<>sum(e.credit) OR j.currency<>i.currency
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

    sig { returns(T::Hash[Symbol, Integer]) }
    def self.call
      ApplicationRecord.uncached do
        ApplicationRecord.transaction(isolation: :repeatable_read) do
          connection = ApplicationRecord.connection
          connection.execute('SET TRANSACTION READ ONLY')
          CHECKS.transform_values do |sql|
            connection.select_value("SELECT count(*) FROM (#{sql}) invalid").to_i
          end
        end
      end
    end
  end
end
