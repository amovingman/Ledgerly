class CreateBillingCore < ActiveRecord::Migration[8.1]
  def change
    enable_extension 'btree_gist'

    create_table :customers do |t|
      t.string :name, null: false, limit: 200
      t.string :email, null: false, limit: 254
      t.string :stripe_customer_id
      t.timestamps
    end
    add_index :customers, 'lower(email)', unique: true, name: 'customers_unique_email'
    add_index :customers, :stripe_customer_id, unique: true
    add_check_constraint :customers, 'length(trim(name)) > 0 AND length(trim(email)) > 0', name: 'customers_nonblank'

    create_table :plans do |t|
      t.string :name, null: false, limit: 200
      t.string :metric, null: false, limit: 64
      t.bigint :unit_amount, null: false
      t.string :currency, null: false, limit: 3
      t.string :billing_interval, null: false, default: 'monthly'
      t.timestamps
    end
    add_check_constraint :plans, "metric ~ '^[a-z][a-z0-9_]{0,63}$'", name: 'plans_metric_format'
    add_check_constraint :plans, 'unit_amount BETWEEN 1 AND 1000000000', name: 'plans_positive_price'
    add_check_constraint :plans, "currency IN ('USD', 'CAD', 'EUR', 'GBP')", name: 'plans_currency'
    add_check_constraint :plans, "billing_interval = 'monthly'", name: 'plans_interval'
    add_check_constraint :plans, 'length(trim(name)) > 0', name: 'plans_nonblank_name'

    create_table :subscriptions do |t|
      t.references :customer, null: false, foreign_key: true
      t.references :plan, null: false, foreign_key: true
      t.string :metric, null: false, limit: 64
      t.bigint :unit_amount, null: false
      t.string :currency, null: false, limit: 3
      t.string :status, null: false, default: 'active'
      t.datetime :starts_at, null: false
      t.datetime :ends_at
      t.string :stripe_subscription_id
      t.timestamps
    end
    add_index :subscriptions, :stripe_subscription_id, unique: true
    add_index :subscriptions, %i[id customer_id metric], unique: true, name: 'subscriptions_usage_identity'
    add_index :subscriptions, %i[id customer_id currency], unique: true, name: 'subscriptions_invoice_identity'
    add_check_constraint :subscriptions, 'unit_amount BETWEEN 1 AND 1000000000', name: 'subscriptions_price'
    add_check_constraint :subscriptions, "currency IN ('USD', 'CAD', 'EUR', 'GBP')", name: 'subscriptions_currency'
    add_check_constraint :subscriptions, "metric ~ '^[a-z][a-z0-9_]{0,63}$'", name: 'subscriptions_metric'
    add_check_constraint :subscriptions, <<~SQL.squish, name: 'subscriptions_lifecycle'
      (status = 'active' AND ends_at IS NULL) OR
      (status = 'cancelled' AND ends_at IS NOT NULL AND ends_at >= starts_at)
    SQL
    add_exclusion_constraint :subscriptions,
                             "customer_id WITH =, metric WITH =, tsrange(starts_at, ends_at, '[)') WITH &&",
                             using: :gist, name: 'subscriptions_no_overlap'

    create_table :invoices do |t|
      t.references :customer, null: false, foreign_key: true
      t.references :subscription, null: false, foreign_key: true
      t.datetime :period_start, null: false
      t.datetime :period_end, null: false
      t.string :currency, null: false, limit: 3
      t.bigint :amount, null: false
      t.string :status, null: false, default: 'issued'
      t.string :stripe_invoice_id
      t.timestamps
    end
    add_index :invoices, %i[subscription_id period_start], unique: true
    add_index :invoices, :stripe_invoice_id, unique: true
    add_foreign_key :invoices, :subscriptions, column: %i[subscription_id customer_id currency],
                                               primary_key: %i[id customer_id currency],
                                               name: 'invoices_subscription_identity'
    add_check_constraint :invoices, <<~SQL.squish, name: 'invoices_calendar_month'
      period_start = date_trunc('month', period_start) AND period_end = period_start + interval '1 month'
    SQL
    add_check_constraint :invoices, 'amount > 0', name: 'invoices_positive_amount'
    add_check_constraint :invoices, "status IN ('issued', 'paid', 'payment_failed', 'refunded')",
                         name: 'invoices_status'

    create_table :invoice_line_items do |t|
      t.references :invoice, null: false, foreign_key: true
      t.string :metric, null: false, limit: 64
      t.bigint :quantity, null: false
      t.bigint :unit_amount, null: false
      t.bigint :amount, null: false
      t.timestamps
    end
    add_index :invoice_line_items, %i[invoice_id metric], unique: true
    add_check_constraint :invoice_line_items, 'quantity > 0 AND unit_amount > 0 AND amount = quantity * unit_amount',
                         name: 'invoice_lines_exact_amount'

    create_table :usage_events do |t|
      t.references :customer, null: false, foreign_key: true
      t.references :subscription, null: false, foreign_key: true
      t.references :invoice_line_item, foreign_key: true
      t.string :metric, null: false, limit: 64
      t.bigint :quantity, null: false
      t.datetime :occurred_at, null: false
      t.string :idempotency_key, null: false, limit: 128
      t.string :request_fingerprint, null: false, limit: 64
      t.timestamps
    end
    add_index :usage_events, %i[customer_id idempotency_key], unique: true
    add_foreign_key :usage_events, :subscriptions, column: %i[subscription_id customer_id metric],
                                                   primary_key: %i[id customer_id metric],
                                                   name: 'usage_subscription_identity'
    add_check_constraint :usage_events, 'quantity BETWEEN 1 AND 1000000000', name: 'usage_positive_quantity'
    add_check_constraint :usage_events, "idempotency_key ~ '^[A-Za-z0-9._:-]{1,128}$'", name: 'usage_key_format'
    add_check_constraint :usage_events, "request_fingerprint ~ '^[a-f0-9]{64}$'", name: 'usage_fingerprint_format'

    create_table :ledger_transactions do |t|
      t.references :invoice, null: false, foreign_key: true
      t.string :journal_type, null: false
      t.string :business_effect_key, null: false
      t.string :currency, null: false, limit: 3
      t.timestamps
    end
    add_index :ledger_transactions, :business_effect_key, unique: true
    add_check_constraint :ledger_transactions, "journal_type IN ('issuance', 'payment', 'refund')", name: 'journal_type'
    add_check_constraint :ledger_transactions, 'length(trim(business_effect_key)) > 0', name: 'journal_effect_nonblank'

    create_table :ledger_entries do |t|
      t.references :ledger_transaction, null: false, foreign_key: true
      t.string :account, null: false
      t.bigint :debit, null: false, default: 0
      t.bigint :credit, null: false, default: 0
      t.timestamps
    end
    add_check_constraint :ledger_entries, '(debit > 0 AND credit = 0) OR (credit > 0 AND debit = 0)',
                         name: 'ledger_one_side'
    add_check_constraint :ledger_entries,
                         "account IN ('accounts_receivable', 'usage_revenue', 'stripe_clearing', 'sales_returns')",
                         name: 'ledger_known_account'
  end
end
