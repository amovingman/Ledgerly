# typed: true

module Billing
  module CustomerBalance
    extend T::Sig

    sig { params(customer: Customer).returns(T::Array[Billing::Types::Balance]) }
    def self.call(customer:)
      ReadCache.fetch(customer: customer, key: 'balance') { calculate(customer) }
    end

    sig { params(customer: Customer).returns(T::Array[Billing::Types::Balance]) }
    def self.calculate(customer)
      totals = LedgerEntry.joins(ledger_transaction: :invoice)
                          .where(invoices: { customer_id: customer.id }, account: 'accounts_receivable')
                          .group('ledger_transactions.currency').sum('ledger_entries.debit - ledger_entries.credit')
      totals.sort.map { |currency, amount| { currency: currency, amount: amount.to_i } }
    end
    private_class_method :calculate
  end
end
