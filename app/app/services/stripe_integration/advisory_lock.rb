require 'digest'

module StripeIntegration
  module AdvisoryLock
    def self.with(key)
      id = Digest::SHA256.digest("ledgerly:#{key}").unpack1('q>')
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        acquired = connection.select_value("SELECT pg_try_advisory_lock(#{id})")
        raise Retryable, 'operation_busy' unless acquired

        begin
          yield
        ensure
          connection.execute("SELECT pg_advisory_unlock(#{id})")
        end
      end
    end
  end
end
