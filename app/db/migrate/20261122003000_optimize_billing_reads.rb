class OptimizeBillingReads < ActiveRecord::Migration[8.1]
  def change
    add_column :customers, :read_version, :bigint, null: false, default: 0
    add_check_constraint :customers, 'read_version >= 0', name: 'customers_read_version_nonnegative'
    add_index :invoices, %i[customer_id created_at id], order: { created_at: :desc, id: :desc },
                                                        name: 'invoices_customer_order'
    add_index :outbox_records, %i[id available_at], where: 'dispatched_at IS NULL', name: 'outbox_pending_dispatch'
    add_index :stripe_events, %i[last_attempted_at id], where: "status = 'received'", name: 'stripe_events_unfinished'
    add_index :invoice_collections, %i[last_attempted_at id], where: "status = 'pending'",
                                                              name: 'collections_unfinished'
  end
end
