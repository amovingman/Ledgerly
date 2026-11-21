# A short-lived probe for verifying the real queue/worker/database path.
class FoundationSmokeJob < ApplicationJob
  queue_as :default

  def perform(probe_key)
    ActiveRecord::Base.connection_pool.with_connection { |connection| connection.execute('SELECT 1') }
    Sidekiq.redis { |redis| redis.call('SET', probe_key, 'ok', 'EX', 60) }
  end
end
