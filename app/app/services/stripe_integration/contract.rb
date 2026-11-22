module StripeIntegration
  module Contract
    def self.check!(remote, expected, code: 'provider_contract_mismatch')
      return if expected.all? { |key, value| remote[key.to_s] == value }

      raise ReviewRequired, code
    end
  end
end
