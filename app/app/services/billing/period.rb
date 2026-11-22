module Billing
  class Period
    attr_reader :start, :finish

    def initialize(value)
      @start = Input.timestamp(value, field: 'period_start')
      unless @start == @start.beginning_of_month
        raise Error.new('invalid_period', 'period_start must be the start of a UTC calendar month.')
      end

      @finish = @start.next_month
    end

    def validate_for!(subscription)
      raise Error.new('period_not_closed', 'Only completed calendar months can be invoiced.') if finish > Time.current
      return if finish > subscription.starts_at && (subscription.ends_at.nil? || start < subscription.ends_at)

      raise Error.new('outside_subscription', 'The billing month does not overlap this subscription.')
    end
  end
end
