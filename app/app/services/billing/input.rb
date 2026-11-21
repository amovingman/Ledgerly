require 'time'
require 'date'

module Billing
  module Input
    MAX_BIGINT = 9_223_372_036_854_775_807
    TIMESTAMP =
      /\A\d{4}-\d{2}-\d{2}T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d{1,6})?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)\z/

    def self.timestamp(value, field:)
      raise ArgumentError unless value.is_a?(String) && TIMESTAMP.match?(value)

      Date.iso8601(value.split('T').first)
      Time.iso8601(value).utc
    rescue ArgumentError
      raise Error.new('invalid_timestamp', "#{field} must be RFC3339 with a timezone and up to six fractional digits.")
    end

    def self.positive_integer(value, field:, maximum: MAX_BIGINT)
      unless value.is_a?(Integer) && value.between?(1, maximum)
        raise Error.new('invalid_integer', "#{field} must be an integer between 1 and #{maximum}.")
      end

      value
    end

    def self.identifier(value)
      value = value.to_i if value.is_a?(String) && /\A[1-9]\d{0,18}\z/.match?(value)
      positive_integer(value, field: 'id')
    end

    def self.text(value, field:, maximum: 200)
      unless value.is_a?(String) && value.present? && value.length <= maximum
        raise Error.new('invalid_input', "#{field} must be a nonblank string of at most #{maximum} characters.")
      end

      value
    end
  end
end
