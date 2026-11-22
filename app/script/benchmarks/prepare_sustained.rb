require Rails.root.join('lib/ledgerly_benchmark/safety')
require Rails.root.join('lib/ledgerly_benchmark/verify')
LedgerlyBenchmark::Safety.check!
raise 'Expected complete 50k fixture' unless Invoice.count == 50_000
raise 'Stop collection work before fixture preparation' if InvoiceCollection.exists? || StripeOperation.exists?

# Application services must be stopped. This deliberately resets only the
# guarded benchmark fixture; invoice/usage/issuance identities remain intact.
ApplicationRecord.transaction do
  ApplicationRecord.connection.execute('SELECT pg_advisory_xact_lock(37650000)')
  OutboxRecord.delete_all
  StripeRefund.delete_all
  StripePayment.delete_all
  journals = LedgerTransaction.where.not(journal_type: 'issuance')
  LedgerEntry.where(ledger_transaction_id: journals).delete_all
  journals.delete_all
  StripeEvent.delete_all
  Invoice.update_all(status: 'issued') # rubocop:disable Rails/SkipsModelValidations
  Customer.update_all(read_version: 0) # rubocop:disable Rails/SkipsModelValidations
end
Sidekiq.redis { |redis| redis.call('FLUSHDB') }
ApplicationRecord.connection.execute('ANALYZE')
puts "SUSTAINED_FIXTURE=#{JSON.generate(LedgerlyBenchmark::Verify.call(fingerprint: true))}"
