# typed: true

module Billing
  class Error < StandardError
    extend T::Sig

    sig { returns(String) }
    attr_reader :code

    sig { returns(Integer) }
    attr_reader :status

    sig { params(code: String, message: String, status: Integer).void }
    def initialize(code, message, status: 422)
      @code = code
      @status = status
      super(message)
    end
  end
end
