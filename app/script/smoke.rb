require 'securerandom'

abort 'Smoke test requires the Sidekiq adapter and a running worker' unless
  Rails.application.config.active_job.queue_adapter == :sidekiq

probe_key = "ledgerly:smoke:#{SecureRandom.uuid}"
begin
  FoundationSmokeJob.perform_later(probe_key)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 20
  loop do
    break if Sidekiq.redis { |redis| redis.call('GET', probe_key) } == 'ok'

    if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      abort 'Sidekiq smoke timed out; check the worker and queue'
    end

    sleep 0.2
  end
  puts 'PASS: Rails -> Redis -> Sidekiq -> PostgreSQL -> Redis'
ensure
  Sidekiq.redis { |redis| redis.call('DEL', probe_key) }
end
