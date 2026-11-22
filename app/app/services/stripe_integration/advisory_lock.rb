# typed: true

require 'digest'

module StripeIntegration
  module AdvisoryLock
    extend T::Sig

    sig do
      type_parameters(:Value).params(key: String,
                                     block: T.proc.returns(T.type_parameter(:Value))).returns(T.type_parameter(:Value))
    end
    def self.with(key, &block)
      id = Digest::SHA256.digest("ledgerly:#{key}").unpack1('q>')
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        acquired = connection.select_value("SELECT pg_try_advisory_lock(#{id})")
        raise Retryable, 'operation_busy' unless acquired

        begin
          block.call
        ensure
          connection.execute("SELECT pg_advisory_unlock(#{id})")
        end
      end
    end
  end
end
