# typed: true

module Billing
  class Period
    extend T::Sig

    sig { returns(Time) }
    attr_reader :start

    sig { returns(Time) }
    attr_reader :finish

    sig { params(value: T.untyped).void }
    def initialize(value)
      @start = Input.timestamp(value, field: 'period_start')
      unless @start == @start.beginning_of_month
        raise Error.new('invalid_period', 'period_start must be the start of a UTC calendar month.')
      end

      @finish = @start.next_month
    end

    sig { params(subscription: Subscription).void }
    def validate_for!(subscription)
      raise Error.new('period_not_closed', 'Only completed calendar months can be invoiced.') if finish > Time.current

      ends_at = subscription.ends_at
      return if finish > subscription.starts_at.to_time && (ends_at.nil? || start < ends_at.to_time)

      raise Error.new('outside_subscription', 'The billing month does not overlap this subscription.')
    end
  end
end
