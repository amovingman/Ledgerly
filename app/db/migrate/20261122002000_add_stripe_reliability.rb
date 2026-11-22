class AddStripeReliability < ActiveRecord::Migration[8.1]
  def change
    create_table :stripe_events do |t|
      t.string :stripe_id, null: false
      t.string :event_type, null: false
      t.string :api_version, null: false
      t.text :raw_payload, null: false
      t.jsonb :payload, null: false
      t.string :status, null: false, default: 'received'
      t.integer :attempts, null: false, default: 0
      t.string :last_error
      t.datetime :last_attempted_at
      t.datetime :processed_at
      t.timestamps
    end
    add_index :stripe_events, :stripe_id, unique: true
    add_check_constraint :stripe_events, "status IN ('received', 'processed', 'ignored', 'dead', 'review')",
                         name: 'stripe_events_status'
    add_check_constraint :stripe_events, 'attempts >= 0 AND octet_length(raw_payload) <= 1048576',
                         name: 'stripe_events_bounds'

    create_table :invoice_collections do |t|
      t.references :invoice, null: false, foreign_key: true, index: { unique: true }
      t.string :status, null: false, default: 'pending'
      t.integer :attempts, null: false, default: 0
      t.string :last_error
      t.datetime :last_attempted_at
      t.datetime :completed_at
      t.timestamps
    end
    add_check_constraint :invoice_collections, "status IN ('pending', 'succeeded', 'dead', 'review')",
                         name: 'collections_status'
    add_check_constraint :invoice_collections, 'attempts >= 0', name: 'collections_attempts'

    create_table :outbox_records do |t|
      t.references :stripe_event, foreign_key: true, index: { unique: true }
      t.references :invoice_collection, foreign_key: true, index: { unique: true }
      t.integer :attempts, null: false, default: 0
      t.datetime :available_at, null: false
      t.datetime :dispatched_at
      t.string :last_error
      t.timestamps
    end
    add_check_constraint :outbox_records, 'num_nonnulls(stripe_event_id, invoice_collection_id) = 1',
                         name: 'outbox_one_target'
    add_check_constraint :outbox_records, 'attempts >= 0', name: 'outbox_attempts'

    create_table :stripe_operations do |t|
      t.references :customer, null: false, foreign_key: true
      t.references :invoice, foreign_key: true
      t.references :invoice_line_item, foreign_key: true
      t.string :operation_key, null: false
      t.string :idempotency_key, null: false
      t.string :kind, null: false
      t.jsonb :payload, null: false
      t.string :remote_id
      t.string :status, null: false, default: 'pending'
      t.datetime :first_attempted_at
      t.datetime :completed_at
      t.timestamps
    end
    add_index :stripe_operations, :operation_key, unique: true
    add_index :stripe_operations, :idempotency_key, unique: true
    add_index :stripe_operations, :remote_id, unique: true, where: "kind <> 'finalize'"
    add_check_constraint :stripe_operations, "kind IN ('customer', 'invoice', 'item', 'finalize')",
                         name: 'operations_kind'
    add_check_constraint :stripe_operations, "status IN ('pending', 'succeeded')", name: 'operations_status'
    add_check_constraint :stripe_operations, <<~SQL.squish, name: 'operations_target'
      (kind = 'customer' AND invoice_id IS NULL AND invoice_line_item_id IS NULL) OR
      (kind IN ('invoice', 'finalize') AND invoice_id IS NOT NULL AND invoice_line_item_id IS NULL) OR
      (kind = 'item' AND invoice_id IS NOT NULL AND invoice_line_item_id IS NOT NULL)
    SQL

    add_reference :ledger_transactions, :stripe_event, foreign_key: true
    add_index :invoices, %i[id currency], unique: true
    create_table :stripe_payments do |t|
      t.references :invoice, null: false, foreign_key: true, index: { unique: true }
      t.references :ledger_transaction, null: false, foreign_key: true, index: { unique: true }
      t.string :charge_id, null: false
      t.string :payment_intent_id, null: false
      t.string :invoice_payment_id, null: false
      t.bigint :amount, null: false
      t.string :currency, null: false, limit: 3
      t.timestamps
    end
    %i[charge_id payment_intent_id invoice_payment_id].each do |column|
      add_index :stripe_payments, column, unique: true
    end
    add_index :stripe_payments, %i[id currency], unique: true
    add_foreign_key :stripe_payments, :invoices, column: %i[invoice_id currency], primary_key: %i[id currency],
                                                 name: 'payments_invoice_currency'
    add_check_constraint :stripe_payments, 'amount > 0', name: 'payments_positive_amount'

    create_table :stripe_refunds do |t|
      t.references :stripe_payment, null: false, foreign_key: true
      t.references :ledger_transaction, null: false, foreign_key: true, index: { unique: true }
      t.string :stripe_id, null: false
      t.bigint :amount, null: false
      t.string :currency, null: false, limit: 3
      t.timestamps
    end
    add_index :stripe_refunds, :stripe_id, unique: true
    add_foreign_key :stripe_refunds, :stripe_payments, column: %i[stripe_payment_id currency],
                                                       primary_key: %i[id currency], name: 'refunds_payment_currency'
    add_check_constraint :stripe_refunds, 'amount > 0', name: 'refunds_positive_amount'
  end
end
