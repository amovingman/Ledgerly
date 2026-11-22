namespace :ledgerly do
  desc 'Check financial invariants in a fresh, consistent read-only snapshot; exit nonzero on violations'
  task audit: :environment do
    checks = Billing::Audit.call
    passed = checks.values.all?(&:zero?)
    puts JSON.pretty_generate({ passed: passed, violations: checks })
    abort 'Financial invariant violations require investigation; do not edit or delete journals.' unless passed
  end

  desc 'Show durable work and queue counts without exposing webhook bodies or job arguments'
  task status: :environment do
    require 'sidekiq/api'
    database = { events: StripeEvent.group(:status).count, collections: InvoiceCollection.group(:status).count,
                 undispatched_outbox: OutboxRecord.where(dispatched_at: nil).count,
                 oldest_undispatched_at: OutboxRecord.where(dispatched_at: nil).minimum(:created_at) }
    queues = begin
      { available: true, webhooks: Sidekiq::Queue.new('webhooks').size,
        billing: Sidekiq::Queue.new('billing').size,
        oldest_webhook_seconds: Sidekiq::Queue.new('webhooks').latency,
        retries: Sidekiq::RetrySet.new.size, dead: Sidekiq::DeadSet.new.size }
    rescue RedisClient::Error, Redis::BaseError
      { available: false, error: 'redis_unavailable' }
    end
    puts JSON.pretty_generate({ database: database, queues: queues })
  end
end
