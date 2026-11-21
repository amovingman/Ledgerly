class HealthController < ActionController::API
  def live
    render json: { status: 'ok' }
  end

  def ready
    checks = { postgres: postgres_ready? ? 'ok' : 'unavailable', redis: redis_ready? ? 'ok' : 'unavailable' }
    available = checks.values.all?('ok')
    render json: { status: available ? 'ok' : 'unavailable', checks: checks },
           status: available ? :ok : :service_unavailable
  end

  private

  def postgres_ready?
    ActiveRecord::Base.connection_pool.with_connection { |connection| connection.select_value('SELECT 1') == 1 }
  rescue ActiveRecord::ActiveRecordError, PG::Error
    false
  end

  def redis_ready?
    client = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'),
                       connect_timeout: 1, read_timeout: 1, write_timeout: 1)
    client.ping == 'PONG'
  rescue Redis::BaseError, RedisClient::Error
    false
  ensure
    client&.close
  end
end
