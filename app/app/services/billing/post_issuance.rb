module Billing
  module PostIssuance
    def self.call(invoice:)
      entries = [LedgerEntry.new(account: 'accounts_receivable', debit: invoice.amount),
                 LedgerEntry.new(account: 'usage_revenue', credit: invoice.amount)]
      invoice.ledger_transactions.create!(journal_type: 'issuance',
                                          business_effect_key: "invoice:#{invoice.id}:issuance",
                                          currency: invoice.currency, ledger_entries: entries)
    end
  end
end
