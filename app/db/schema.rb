# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_21_235500) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "btree_gist"
  enable_extension "pg_catalog.plpgsql"

  create_table "customers", force: :cascade do |t|
    t.string "name", limit: 200, null: false
    t.string "email", limit: 254, null: false
    t.string "stripe_customer_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "lower((email)::text)", name: "customers_unique_email", unique: true
    t.index ["stripe_customer_id"], name: "index_customers_on_stripe_customer_id", unique: true
    t.check_constraint "length(TRIM(BOTH FROM name)) > 0 AND length(TRIM(BOTH FROM email)) > 0", name: "customers_nonblank"
  end

  create_table "invoice_line_items", force: :cascade do |t|
    t.bigint "invoice_id", null: false
    t.string "metric", limit: 64, null: false
    t.bigint "quantity", null: false
    t.bigint "unit_amount", null: false
    t.bigint "amount", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["invoice_id", "metric"], name: "index_invoice_line_items_on_invoice_id_and_metric", unique: true
    t.index ["invoice_id"], name: "index_invoice_line_items_on_invoice_id"
    t.check_constraint "quantity > 0 AND unit_amount > 0 AND amount = (quantity * unit_amount)", name: "invoice_lines_exact_amount"
  end

  create_table "invoices", force: :cascade do |t|
    t.bigint "customer_id", null: false
    t.bigint "subscription_id", null: false
    t.datetime "period_start", null: false
    t.datetime "period_end", null: false
    t.string "currency", limit: 3, null: false
    t.bigint "amount", null: false
    t.string "status", default: "issued", null: false
    t.string "stripe_invoice_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_invoices_on_customer_id"
    t.index ["stripe_invoice_id"], name: "index_invoices_on_stripe_invoice_id", unique: true
    t.index ["subscription_id", "period_start"], name: "index_invoices_on_subscription_id_and_period_start", unique: true
    t.index ["subscription_id"], name: "index_invoices_on_subscription_id"
    t.check_constraint "amount > 0", name: "invoices_positive_amount"
    t.check_constraint "period_start = date_trunc('month'::text, period_start) AND period_end = (period_start + 'P1M'::interval)", name: "invoices_calendar_month"
    t.check_constraint "status::text = ANY (ARRAY['issued'::character varying::text, 'paid'::character varying::text, 'payment_failed'::character varying::text, 'refunded'::character varying::text])", name: "invoices_status"
  end

  create_table "ledger_entries", force: :cascade do |t|
    t.bigint "ledger_transaction_id", null: false
    t.string "account", null: false
    t.bigint "debit", default: 0, null: false
    t.bigint "credit", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ledger_transaction_id"], name: "index_ledger_entries_on_ledger_transaction_id"
    t.check_constraint "account::text = ANY (ARRAY['accounts_receivable'::character varying::text, 'usage_revenue'::character varying::text, 'stripe_clearing'::character varying::text, 'sales_returns'::character varying::text])", name: "ledger_known_account"
    t.check_constraint "debit > 0 AND credit = 0 OR credit > 0 AND debit = 0", name: "ledger_one_side"
  end

  create_table "ledger_transactions", force: :cascade do |t|
    t.bigint "invoice_id", null: false
    t.string "journal_type", null: false
    t.string "business_effect_key", null: false
    t.string "currency", limit: 3, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_effect_key"], name: "index_ledger_transactions_on_business_effect_key", unique: true
    t.index ["invoice_id"], name: "index_ledger_transactions_on_invoice_id"
    t.index ["invoice_id"], name: "one_issuance_journal_per_invoice", unique: true, where: "((journal_type)::text = 'issuance'::text)"
    t.check_constraint "journal_type::text = ANY (ARRAY['issuance'::character varying::text, 'payment'::character varying::text, 'refund'::character varying::text])", name: "journal_type"
    t.check_constraint "length(TRIM(BOTH FROM business_effect_key)) > 0", name: "journal_effect_nonblank"
  end

  create_table "plans", force: :cascade do |t|
    t.string "name", limit: 200, null: false
    t.string "metric", limit: 64, null: false
    t.bigint "unit_amount", null: false
    t.string "currency", limit: 3, null: false
    t.string "billing_interval", default: "monthly", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.check_constraint "billing_interval::text = 'monthly'::text", name: "plans_interval"
    t.check_constraint "currency::text = ANY (ARRAY['USD'::character varying::text, 'CAD'::character varying::text, 'EUR'::character varying::text, 'GBP'::character varying::text])", name: "plans_currency"
    t.check_constraint "length(TRIM(BOTH FROM name)) > 0", name: "plans_nonblank_name"
    t.check_constraint "metric::text ~ '^[a-z][a-z0-9_]{0,63}$'::text", name: "plans_metric_format"
    t.check_constraint "unit_amount >= 1 AND unit_amount <= 1000000000", name: "plans_positive_price"
  end

  create_table "subscriptions", force: :cascade do |t|
    t.bigint "customer_id", null: false
    t.bigint "plan_id", null: false
    t.string "metric", limit: 64, null: false
    t.bigint "unit_amount", null: false
    t.string "currency", limit: 3, null: false
    t.string "status", default: "active", null: false
    t.datetime "starts_at", null: false
    t.datetime "ends_at"
    t.string "stripe_subscription_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_subscriptions_on_customer_id"
    t.index ["id", "customer_id", "currency"], name: "subscriptions_invoice_identity", unique: true
    t.index ["id", "customer_id", "metric"], name: "subscriptions_usage_identity", unique: true
    t.index ["plan_id"], name: "index_subscriptions_on_plan_id"
    t.index ["stripe_subscription_id"], name: "index_subscriptions_on_stripe_subscription_id", unique: true
    t.check_constraint "currency::text = ANY (ARRAY['USD'::character varying::text, 'CAD'::character varying::text, 'EUR'::character varying::text, 'GBP'::character varying::text])", name: "subscriptions_currency"
    t.check_constraint "metric::text ~ '^[a-z][a-z0-9_]{0,63}$'::text", name: "subscriptions_metric"
    t.check_constraint "status::text = 'active'::text AND ends_at IS NULL OR status::text = 'cancelled'::text AND ends_at IS NOT NULL AND ends_at >= starts_at", name: "subscriptions_lifecycle"
    t.check_constraint "unit_amount >= 1 AND unit_amount <= 1000000000", name: "subscriptions_price"
    t.exclusion_constraint "customer_id WITH =, metric WITH =, tsrange(starts_at, ends_at, '[)'::text) WITH &&", using: :gist, name: "subscriptions_no_overlap"
  end

  create_table "usage_events", force: :cascade do |t|
    t.bigint "customer_id", null: false
    t.bigint "subscription_id", null: false
    t.bigint "invoice_line_item_id"
    t.string "metric", limit: 64, null: false
    t.bigint "quantity", null: false
    t.datetime "occurred_at", null: false
    t.string "idempotency_key", limit: 128, null: false
    t.string "request_fingerprint", limit: 64, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id", "idempotency_key"], name: "index_usage_events_on_customer_id_and_idempotency_key", unique: true
    t.index ["customer_id"], name: "index_usage_events_on_customer_id"
    t.index ["invoice_line_item_id"], name: "index_usage_events_on_invoice_line_item_id"
    t.index ["subscription_id"], name: "index_usage_events_on_subscription_id"
    t.check_constraint "idempotency_key::text ~ '^[A-Za-z0-9._:-]{1,128}$'::text", name: "usage_key_format"
    t.check_constraint "quantity >= 1 AND quantity <= 1000000000", name: "usage_positive_quantity"
    t.check_constraint "request_fingerprint::text ~ '^[a-f0-9]{64}$'::text", name: "usage_fingerprint_format"
  end

  add_foreign_key "invoice_line_items", "invoices"
  add_foreign_key "invoices", "customers"
  add_foreign_key "invoices", "subscriptions"
  add_foreign_key "invoices", "subscriptions", column: ["subscription_id", "customer_id", "currency"], primary_key: ["id", "customer_id", "currency"], name: "invoices_subscription_identity"
  add_foreign_key "ledger_entries", "ledger_transactions"
  add_foreign_key "ledger_transactions", "invoices"
  add_foreign_key "subscriptions", "customers"
  add_foreign_key "subscriptions", "plans"
  add_foreign_key "usage_events", "customers"
  add_foreign_key "usage_events", "invoice_line_items"
  add_foreign_key "usage_events", "subscriptions"
  add_foreign_key "usage_events", "subscriptions", column: ["subscription_id", "customer_id", "metric"], primary_key: ["id", "customer_id", "metric"], name: "usage_subscription_identity"
end
