module LedgerlyBenchmark
  module QueueProfile
    class Middleware
      def call(_worker, job, _queue)
        row = { jid: job.fetch('jid'), event_id: job.fetch('args').first, stages: {} }
        Thread.current[:queue_profile] = row
        wall = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        cpu = Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID)
        gc = GC.stat(:time)
        yield
      ensure
        row[:wall_ms] = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - wall) * 1000
        row[:thread_cpu_ms] = (Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID) - cpu) * 1000
        row[:overlapping_process_gc_ms] = GC.stat(:time) - gc
        row[:finished_at] = Time.now.utc.iso8601(6)
        QueueProfile.write(row) if row[:wall_ms] >= 100
        Thread.current[:queue_profile] = nil
      end
    end

    def self.write(row)
      @mutex.synchronize { @file.puts(JSON.generate(row)) }
    end

    def self.measure(name)
      row = Thread.current[:queue_profile]
      return yield unless row

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
    ensure
      if row
        stage = (row[:stages][name] ||= { calls: 0, ms: 0.0 })
        stage[:calls] += 1
        stage[:ms] += (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
      end
    end

    def self.wrap(klass, method, name)
      klass.prepend(Module.new do
        define_method(method) do |*args, **kwargs, &block|
          QueueProfile.measure(name) { super(*args, **kwargs, &block) }
        end
      end)
    end

    def self.install
      @mutex = Mutex.new
      @file = File.open('/tmp/ledgerly-queue-profile.ndjson', 'a')
      @file.sync = true
      wrap(StripeIntegration::ResolveSnapshot, :call, 'snapshot')
      wrap(StripeIntegration::PostEffects, :call, 'posting')
      wrap(StripeIntegration::Gateway, :api, 'provider')
      ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, start, finish, _id, payload|
        row = Thread.current[:queue_profile]
        next unless row && payload[:name] != 'SCHEMA'

        stage = (row[:stages]['sql'] ||= { calls: 0, ms: 0.0, max_ms: 0.0 })
        duration = (finish - start) * 1000
        stage[:calls] += 1
        stage[:ms] += duration
        stage[:max_ms] = [stage[:max_ms], duration].max
      end
      Sidekiq.configure_server { |config| config.server_middleware { |chain| chain.add(Middleware) } }
    end
  end
end
