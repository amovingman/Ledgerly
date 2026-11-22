module StripeIntegration
  class Failure < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super
    end
  end
end
