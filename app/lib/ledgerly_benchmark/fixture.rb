module LedgerlyBenchmark
  module Fixture
    SEED = 20_261_121
    COUNT = 50_000
    VERSION = 'v1'.freeze
    CURRENCIES = %w[USD CAD EUR GBP].freeze

    def self.attributes(id)
      raise ArgumentError, 'Invoice outside fixture' unless (1..COUNT).cover?(id)

      customer, subscription, metric, month = coordinates(id)
      price = (metric * 3) + 4
      quantity = (1..3).sum { |part| (((id * 17) + (part * 13) + SEED) % 997) + 10 }
      { id: id, customer_id: customer, subscription_id: subscription, metric: "metric_#{metric}",
        currency: CURRENCIES[(customer - 1) % 4].downcase, unit_amount: price, quantity: quantity,
        amount: price * quantity, month: month }
    end

    def self.coordinates(id)
      case id
      when 1..10_000
        offset = id - 1
        [(offset / 1000) + 1, (offset / 50) + 1, ((offset / 50) % 20) + 1, offset % 50]
      when 10_001..28_000
        offset = id - 10_001
        [(offset / 200) + 11, (offset / 50) + 201, ((offset / 50) % 4) + 1, offset % 50]
      when 28_001..38_000
        offset = id - 28_001
        [(offset / 25) + 101, (offset / 25) + 561, 1, (offset % 25) + 25]
      else
        offset = id - 38_001
        [(offset / 24) + 501, (offset / 24) + 961, 1, (offset % 24) + 26]
      end
    end

    def self.refund_amount(id)
      amount = attributes(id).fetch(:amount)
      return amount / 4 if id % 20 == 2
      return amount if id % 20 == 3

      0
    end
  end
end
