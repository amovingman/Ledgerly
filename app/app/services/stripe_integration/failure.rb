# typed: true

module StripeIntegration
  class Failure < StandardError
    extend T::Sig

    sig { returns(String) }
    attr_reader :code

    sig { params(code: String).void }
    def initialize(code)
      @code = code
      super
    end
  end
end
