# typed: true

module StripeIntegration
  module OutboxDispatcher
    extend T::Sig

    sig { params(record_id: T.nilable(Integer), limit: Integer).void }
    def self.call(record_id: nil, limit: 100)
      scope = OutboxRecord.where(dispatched_at: nil).where(available_at: ..Time.current).order(:id)
      scope = scope.where(id: record_id) if record_id
      scope.limit(limit).pluck(:id).each { |id| dispatch(OutboxRecord.find(id)) }
    end

    sig { params(record: OutboxRecord).void }
    def self.dispatch(record)
      record.with_lock do
        return if record.dispatched_at || record.available_at > Time.current

        if T.must(record.target).terminal?
          record.update!(dispatched_at: Time.current, last_error: nil)
          return
        end
        enqueue(record)
      end
    end

    sig { params(record: OutboxRecord).void }
    def self.enqueue(record)
      job = record.stripe_event_id ? ProcessEventJob : CollectInvoiceJob
      target_id = record.stripe_event_id || record.invoice_collection_id
      job.perform_async(target_id)
      record.update!(dispatched_at: Time.current, attempts: record.attempts + 1, last_error: nil)
    rescue RedisClient::Error, Redis::BaseError
      defer(record)
    end

    sig { params(record: OutboxRecord).void }
    def self.defer(record)
      delay = [2**[record.attempts, 8].min, 300].min
      record.update!(available_at: Time.current + delay.seconds, attempts: record.attempts + 1,
                     last_error: 'queue_unavailable')
    end
    private_class_method :dispatch, :enqueue, :defer
  end
end
