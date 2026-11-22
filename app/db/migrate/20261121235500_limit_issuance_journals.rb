class LimitIssuanceJournals < ActiveRecord::Migration[8.1]
  def change
    add_index :ledger_transactions, :invoice_id, unique: true, where: "journal_type = 'issuance'",
                                                 name: 'one_issuance_journal_per_invoice'
  end
end
