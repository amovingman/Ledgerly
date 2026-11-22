# typed: true

module StripeIntegration
  module RecoverySweep
    extend T::Sig

    sig { void }
    def self.call
      cutoff = 5.minutes.ago
      scope = OutboxRecord.where(dispatched_at: ..cutoff)
      stale_events = unfinished(StripeEvent.where(status: 'received'), cutoff)
      stale_collections = unfinished(InvoiceCollection.where(status: 'pending'), cutoff)
      scope.where(stripe_event_id: stale_events).find_each { |record| recover(record) }
      scope.where(invoice_collection_id: stale_collections).find_each { |record| recover(record) }
      OutboxDispatcher.call
    end

    sig { params(scope: ActiveRecord::Relation, cutoff: ActiveSupport::TimeWithZone).returns(ActiveRecord::Relation) }
    def self.unfinished(scope, cutoff)
      scope.where(last_attempted_at: nil).or(scope.where(last_attempted_at: ..cutoff)).select(:id)
    end
    private_class_method :unfinished

    sig { params(record: OutboxRecord).void }
    def self.recover(record)
      record.with_lock do
        target = T.must(record.target).reload
        return if target.terminal? || (target.last_attempted_at && target.last_attempted_at > 5.minutes.ago)

        record.update!(dispatched_at: nil, available_at: Time.current, last_error: nil)
      end
    end
    private_class_method :recover

    sig { params(target: T.any(StripeEvent, InvoiceCollection)).void }
    def self.replay(target)
      target.with_lock do
        unless %w[dead review].include?(target.status)
          raise Billing::Error.new('not_replayable', 'Only dead or review work can be manually replayed.', status: 409)
        end

        target.update!(status: target.is_a?(StripeEvent) ? 'received' : 'pending', attempts: 0,
                       last_error: nil, last_attempted_at: nil)
        T.must(target.outbox_record).update!(dispatched_at: nil, available_at: Time.current, last_error: nil)
      end
      OutboxDispatcher.call(record_id: T.must(target.outbox_record).id)
    end
  end
end
