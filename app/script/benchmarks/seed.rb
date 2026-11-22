require Rails.root.join('lib/ledgerly_benchmark/safety')
require Rails.root.join('lib/ledgerly_benchmark/verify')
LedgerlyBenchmark::Safety.check!
connection = ActiveRecord::Base.connection
models = %w[outbox_records stripe_refunds stripe_payments ledger_entries ledger_transactions stripe_operations
            invoice_collections stripe_events usage_events invoice_line_items invoices subscriptions plans customers]
connection.transaction do
  connection.execute('SELECT pg_advisory_xact_lock(37650000)')
  if Invoice.exists? && ENV['RESET_BENCHMARK_DATA'] != '1'
    puts JSON.pretty_generate(LedgerlyBenchmark::Verify.call(fingerprint: true))
    exit 0 # Reusing an existing valid fixture never clears live benchmark jobs.
  end

  connection.execute("TRUNCATE #{models.join(', ')} RESTART IDENTITY CASCADE")
  connection.execute(Rails.root.join('script/benchmarks/seed.sql').read)
  models.each do |table|
    connection.execute(<<~SQL.squish)
      SELECT setval(pg_get_serial_sequence('#{table}','id'), COALESCE(MAX(id),1), MAX(id) IS NOT NULL) FROM #{table}
    SQL
  end
end
# Dedicated Redis only; clear stale jobs before starting benchmark workers.
Sidekiq.redis { |redis| redis.call('FLUSHDB') }
connection.execute('ANALYZE')
puts JSON.pretty_generate(LedgerlyBenchmark::Verify.call(fingerprint: true))
