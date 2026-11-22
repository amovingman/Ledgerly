# typed: strict

module Billing
  module Types
    Balance = T.type_alias { { currency: String, amount: Integer } }
    Usage = T.type_alias { { metric: String, quantity: Integer, occurred_at: Time } }
  end
end
