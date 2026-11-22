# typed: true

module StripeIntegration
  module Contract
    extend T::Sig

    sig { params(remote: StripeIntegration::Types::JsonObject, expected: StripeIntegration::Types::Parameters, code: String).void }
    def self.check!(remote, expected, code: 'provider_contract_mismatch')
      return if expected.all? { |key, value| remote[key.to_s] == value }

      raise ReviewRequired, code
    end
  end
end
