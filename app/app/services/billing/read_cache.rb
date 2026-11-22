require 'json'

module Billing
  module ReadCache
    TTL = 30
    MAX_BYTES = 65_536

    def self.fetch(customer:, key:, cacheable: true, &)
      return yield unless enabled? && cacheable && !Customer.connection.transaction_open?

      identity = cache_key(customer, key)
      cached = read(identity)
      notify(cached.nil? ? 'miss' : 'hit')
      return cached unless cached.nil?

      value = Customer.uncached(&)
      write(identity, value)
      value
    end

    def self.enabled?
      ENV.fetch('READ_CACHE_ENABLED', '1') == '1'
    end

    def self.cache_key(customer, key)
      version = Customer.uncached { Customer.where(id: customer.id).pick(:read_version) }
      "ledgerly:reads:v1:#{customer.id}:#{version}:#{key}"
    end

    def self.notify(status)
      ActiveSupport::Notifications.instrument('read_cache.billing', status: status)
    end

    def self.client
      @client ||= Redis.new(url: ENV.fetch('REDIS_URL'), connect_timeout: 0.02, read_timeout: 0.02, write_timeout: 0.02,
                            reconnect_attempts: 0)
    end

    def self.read(key)
      return if unavailable?

      encoded = client.get(key)
      JSON.parse(encoded, symbolize_names: true) if encoded
    rescue Redis::BaseError, RedisClient::Error, JSON::ParserError, TypeError
      @retry_after = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1
      nil
    end

    def self.write(key, value)
      return if unavailable?

      encoded = JSON.generate(value)
      client.set(key, encoded, ex: TTL) if encoded.bytesize <= MAX_BYTES
    rescue Redis::BaseError, RedisClient::Error
      @retry_after = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1
      nil
    end

    def self.unavailable?
      @retry_after && @retry_after > Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
    private_class_method :client, :read, :write, :unavailable?, :notify, :cache_key
  end
end
