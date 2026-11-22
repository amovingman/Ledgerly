require Rails.root.join('lib/ledgerly_benchmark/safety')
LedgerlyBenchmark::Safety.check!
connection = ActiveRecord::Base.connection
queries = {
  invoice_list_first_page: 'SELECT * FROM invoices WHERE customer_id=1 ORDER BY created_at DESC,id DESC LIMIT 100',
  invoice_list_deep_page: <<~SQL.squish,
    SELECT * FROM invoices WHERE customer_id=1 ORDER BY created_at DESC,id DESC LIMIT 100 OFFSET 900
  SQL
  invoice_count: 'SELECT count(*) FROM invoices WHERE customer_id=1',
  balance: <<~SQL.squish
    SELECT j.currency,sum(e.debit-e.credit) FROM ledger_entries e JOIN ledger_transactions j
    ON j.id=e.ledger_transaction_id JOIN invoices i ON i.id=j.invoice_id
    WHERE i.customer_id=1 AND e.account='accounts_receivable' GROUP BY j.currency
  SQL
}
plans = queries.transform_values do |sql|
  { sql: sql, explain: JSON.parse(connection.select_value("EXPLAIN (ANALYZE,BUFFERS,SETTINGS,FORMAT JSON) #{sql}")) }
end
indexes = connection.select_all(<<~SQL.squish).to_a
  SELECT tablename,indexname,indexdef FROM pg_indexes WHERE schemaname='public' ORDER BY tablename,indexname
SQL
puts JSON.pretty_generate({ plans: plans, indexes: indexes, cache_store: Rails.cache.class.name,
                            ruby: RUBY_DESCRIPTION, rails: Rails.version,
                            postgres: connection.select_value('SELECT version()'),
                            sidekiq_concurrency: ENV.fetch('RAILS_MAX_THREADS'),
                            database: connection.select_value('SELECT current_database()') })
