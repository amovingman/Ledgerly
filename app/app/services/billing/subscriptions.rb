# typed: true

module Billing
  module Subscriptions
    extend T::Sig

    sig { params(customer: Customer, plan: Plan, starts_at: T.untyped).returns(Subscription) }
    def self.create(customer:, plan:, starts_at: nil)
      start = starts_at.nil? ? Time.current : Input.timestamp(starts_at, field: 'starts_at')
      customer.with_lock do
        customer.subscriptions.create!(plan: plan, starts_at: start, metric: plan.metric,
                                       unit_amount: plan.unit_amount, currency: plan.currency)
      end
    rescue ActiveRecord::StatementInvalid => e
      raise unless e.cause.is_a?(PG::ExclusionViolation)

      raise Error.new('subscription_overlap', 'This customer already has a subscription for that metric and interval.',
                      status: 409)
    end

    sig { params(subscription: Subscription).returns(Subscription) }
    def self.cancel(subscription:)
      T.must(subscription.customer).with_lock do
        subscription.reload
        return subscription if subscription.status == 'cancelled'

        subscription.update!(status: 'cancelled', ends_at: [Time.current, subscription.starts_at].max)
        subscription
      end
    end
  end
end
