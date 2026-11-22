require_relative 'safety'
require_relative 'provider'
require_relative 'verify'

module LedgerlyBenchmark
  # Separate correctness replay: real PostgreSQL/signatures/services, in-process
  # canonical provider. HTTP and Sidekiq throughput are measured separately.
  class FullReplay
    class Gateway
      KINDS = { 'invoice' => 'invoices', 'payment_intent' => 'payment_intents', 'charge' => 'charges',
                'invoice_payment' => 'invoice_payments', 'refund' => 'refunds' }.freeze

      def initialize
        @provider = Provider.new
      end

      def retrieve(kind, id)
        canonical(kind, id)
      end

      def list(kind, parameters)
        id = parameters[:invoice] || parameters[:charge] || parameters.dig(:payment, :payment_intent)
        canonical(kind, id)
      end

      private

      def canonical(kind, id)
        number = id.to_s[/\A(?:in|pi|ch)_bench_(\d+)\z/, 1]
        raise 'Unknown fixture identity' unless number

        JSON.parse(JSON.generate(@provider.resource(KINDS.fetch(kind), number.to_i)))
      end
    end

    def initialize(progress: nil)
      @progress = progress
      @lock = Mutex.new
      @completed = 0
      @failures = []
      @body_created = Time.now.to_i
    end

    def call
      Safety.check!
      prepare
      initial = Verify.call
      jobs = tasks
      @total = jobs.size
      @queue = Queue.new
      jobs.each { |job| @queue << job }
      4.times { @queue << nil }
      @started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      Array.new(4) { Thread.new { worker } }.each(&:value)
      raise "Replay failed: #{@failures.first(10)}" unless @failures.empty?

      final = Verify.call
      validate!
      { passed: true, invoices: 50_000, signed_deliveries: @total, unique_events: 60_000,
        initial: initial, final: final, workers: 4, failures: 0, elapsed_seconds: elapsed,
        payment_origin_event_types: LedgerTransaction.where(journal_type: 'payment').joins(:stripe_event)
                                                     .group('stripe_events.event_type').count,
        scope: 'Service-level signed replay; PostgreSQL; in-process provider; no HTTP throughput claim.' }
    end

    private

    def prepare
      raise 'Expected the complete 50k fixture.' unless Invoice.count == 50_000

      ApplicationRecord.transaction do
        OutboxRecord.delete_all
        StripeRefund.delete_all
        StripePayment.delete_all
        LedgerEntry.where(ledger_transaction_id: LedgerTransaction.where.not(journal_type: 'issuance')).delete_all
        LedgerTransaction.where.not(journal_type: 'issuance').delete_all
        StripeEvent.delete_all
        # Guarded fixture setup deliberately resets historical immutable states.
        Invoice.update_all(status: 'issued') # rubocop:disable Rails/SkipsModelValidations
        Customer.update_all(read_version: 0) # rubocop:disable Rails/SkipsModelValidations
      end
      Sidekiq.redis { |redis| redis.call('FLUSHDB') }
    end

    def tasks
      jobs = (1..50_000).flat_map do |id|
        events = [[id, 'invoice.paid']]
        events << [id, 'charge.refunded'] if [2, 3].include?(id % 20)
        events << [id, 'invoice.payment_failed'] if id % 10 == 1
        events
      end
      (jobs * 3).shuffle(random: Random.new(20_261_121))
    end

    def worker
      gateway = Gateway.new
      ActiveRecord::Base.connection_pool.with_connection do
        while (job = @queue.pop)
          deliver(job, gateway)
          progress
        end
      end
    end

    def deliver(job, gateway)
      id, type = job
      prefix = type == 'charge.refunded' ? 'ch' : 'in'
      payload = { id: "evt_full_#{id}_#{type.tr('.', '_')}", object: 'event', type: type,
                  livemode: false, created: @body_created, api_version: StripeIntegration::Settings::API_VERSION,
                  data: { object: { id: "#{prefix}_bench_#{id}", object: prefix == 'ch' ? 'charge' : 'invoice' } } }
      raw = JSON.generate(payload)
      time = Time.current
      digest = Stripe::Webhook::Signature.compute_signature(time, raw, StripeIntegration::Settings.webhook_secret!)
      signature = Stripe::Webhook::Signature.generate_header(time, digest)
      event = StripeIntegration::ReceiveEvent.call(raw: raw, signature: signature).record
      process(event, gateway)
    rescue StandardError => e
      @lock.synchronize { @failures << { invoice_id: id, type: type, error: e.class.name } }
    end

    def process(event, gateway)
      StripeIntegration::ProcessEvent.new(event: event, gateway: gateway).call
    rescue StripeIntegration::Retryable => e
      raise unless e.code == 'operation_busy'

      sleep 0.002
      retry
    end

    def progress
      @lock.synchronize do
        @completed += 1
        return unless (@completed % 1000).zero?

        @progress&.call(deliveries_completed: @completed, total_deliveries: @total,
                        elapsed_seconds: elapsed, failures: @failures.size)
      end
    end

    def validate_receipts!
      return if StripeEvent.count == 60_000 && StripeEvent.where(status: 'processed').count == 60_000

      raise 'Missing unique receipts'
    end

    def validate!
      validate_receipts!
      raise 'Duplicate/missing effects' unless StripePayment.count == 50_000 && StripeRefund.count == 5000
      raise 'Incorrect journals' unless LedgerTransaction.count == 105_000 && LedgerEntry.count == 210_000

      balances = LedgerEntry.where(account: 'accounts_receivable').joins(:ledger_transaction)
                            .group('ledger_transactions.currency').sum('debit-credit')
      raise 'Nonzero receivables' unless balances.values.all?(&:zero?)
    end

    def elapsed
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started
    end
  end
end
