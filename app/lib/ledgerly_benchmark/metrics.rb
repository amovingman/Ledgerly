require 'sidekiq/api'
require_relative 'verify'

module LedgerlyBenchmark
  class Metrics
    def initialize(app)
      @app = app
      ActiveSupport::Notifications.subscribe('read_cache.billing') do |*arguments|
        Thread.current[:benchmark_sql]&.store(:cache_status, arguments.last.fetch(:status))
      end
      ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, start, finish, _id, payload|
        stats = Thread.current[:benchmark_sql]
        if stats && %w[SCHEMA TRANSACTION].exclude?(payload[:name]) && !payload[:cached]
          stats[:queries] += 1
          stats[:milliseconds] += (finish - start) * 1000
        end
      end
    end

    def call(env)
      return benchmark_route(env) if env['PATH_INFO'].start_with?('/_benchmark/')

      previous = Thread.current[:benchmark_sql]
      stats = { queries: 0, milliseconds: 0.0 }
      Thread.current[:benchmark_sql] = stats
      status, headers, body = @app.call(env)
      headers['x-benchmark-sql-queries'] = stats[:queries].to_s
      headers['x-benchmark-cache-status'] = stats.fetch(:cache_status, 'off')
      headers['x-benchmark-sql-ms'] = stats[:milliseconds].round(3).to_s
      [status, headers, body]
    ensure
      Thread.current[:benchmark_sql] = previous
    end

    private

    def benchmark_route(env)
      return json({ error: 'unauthorized' }, 401) unless env['HTTP_AUTHORIZATION'] == "Bearer #{ENV.fetch('API_KEY')}"

      case env['PATH_INFO']
      when '/_benchmark/cache/clear' then clear_cache(env)
      when '/_benchmark/dataset' then json(Verify.call)
      when '/_benchmark/stats' then json(stats(Rack::Request.new(env).params.fetch('since', '0')))
      else json({ error: 'not_found' }, 404)
      end
    end

    def clear_cache(env)
      return json({ error: 'method_not_allowed' }, 405) unless env['REQUEST_METHOD'] == 'POST'

      redis = Redis.new(url: ENV.fetch('REDIS_URL'))
      keys = redis.scan_each(match: 'ledgerly:reads:v1:*').to_a
      keys.each { |key| redis.del(key) }
      json({ cleared: keys.size, read_cache_enabled: Billing::ReadCache.enabled? })
    end

    def stats(since)
      identity = Integer(since, 10)
      raise ArgumentError, 'Invalid observation boundary' if identity.negative?

      connection = ActiveRecord::Base.connection
      processing = JSON.parse(connection.select_value(<<~SQL.squish))
        SELECT json_build_object('database_time',clock_timestamp(),'total',count(*),
          'processed',count(*) FILTER (WHERE status='processed'),
          'ignored',count(*) FILTER (WHERE status='ignored'),'received',count(*) FILTER (WHERE status='received'),
          'dead',count(*) FILTER (WHERE status='dead'),'review',count(*) FILTER (WHERE status='review'),
          'retried_events',count(*) FILTER (WHERE attempts>1),'max_attempts',COALESCE(max(attempts),0),
          'receipt_to_attempt_ms',percentile_cont(ARRAY[0.5,0.95,0.99]) WITHIN GROUP
            (ORDER BY extract(epoch from last_attempted_at-created_at)*1000),
          'completion_ms',percentile_cont(ARRAY[0.5,0.95,0.99]) WITHIN GROUP
            (ORDER BY extract(epoch from processed_at-created_at)*1000))
        FROM stripe_events WHERE id>#{identity}
      SQL
      processing.merge('max_event_id' => StripeEvent.maximum(:id), 'queues' => Sidekiq::Stats.new.queues,
                       'oldest_webhook_queue_latency_seconds' => Sidekiq::Queue.new('webhooks').latency,
                       'retry_size' => Sidekiq::RetrySet.new.size, 'scheduled_size' => Sidekiq::ScheduledSet.new.size,
                       'dead_size' => Sidekiq::DeadSet.new.size)
    end

    def json(body, status = 200)
      [status, { 'content-type' => 'application/json' }, [JSON.generate(body)]]
    end
  end
end
