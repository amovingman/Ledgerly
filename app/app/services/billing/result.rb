# typed: strict

module Billing
  class Result
    extend T::Sig
    extend T::Generic

    Record = type_member { { upper: ApplicationRecord } }

    sig { returns(Record) }
    attr_reader :record

    sig { returns(T::Boolean) }
    attr_reader :replayed

    sig { params(record: Record, replayed: T::Boolean).void }
    def initialize(record:, replayed:)
      @record = record
      @replayed = replayed
      freeze
    end
  end
end
