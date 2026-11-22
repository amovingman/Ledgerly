module LedgerlyBenchmark
  module Safety
    def self.check!
      expected = { 'DB_HOST' => 'benchmark-postgres', 'REDIS_URL' => 'redis://benchmark-redis:6379/0',
                   'STRIPE_SECRET_KEY' => 'sk_test_benchmark', 'STRIPE_WEBHOOK_SECRET' => 'whsec_benchmark' }
      valid = Rails.env.benchmark? && expected.all? { |key, value| ENV[key] == value }
      raise 'Benchmark requires the dedicated benchmark environment and isolated services.' unless valid
      raise 'DATABASE_URL must not override the benchmark database.' if ENV['DATABASE_URL'].present?

      config = ActiveRecord::Base.configurations.configs_for(env_name: 'benchmark', name: 'primary')
      raise 'Unexpected benchmark database.' unless config.database == 'ledgerly_benchmark'
    end
  end
end
