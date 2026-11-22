# typed: strict

module StripeIntegration
  module Types
    # JSON remains dynamic until provider contract checks have validated it.
    JsonObject = T.type_alias { T::Hash[String, T.untyped] }
    Parameters = T.type_alias { T::Hash[T.any(String, Symbol), T.untyped] }
    Payment = T.type_alias do
      { allocation: JsonObject, intent: JsonObject, charge: JsonObject, refunds: T::Array[JsonObject] }
    end
    Snapshot = T.type_alias { { invoice: Invoice, remote: JsonObject, payment: T.nilable(Payment) } }
  end
end
