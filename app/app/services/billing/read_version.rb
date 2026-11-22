module Billing
  module ReadVersion
    def self.advance!(customer_id)
      # The caller's invoice/journal save transaction commits this invalidation
      # atomically. Old fills may finish later, but their versioned keys stay obsolete.
      raise 'Read invalidation requires a database transaction.' unless Customer.connection.transaction_open?

      Customer.where(id: customer_id).update_all('read_version = read_version + 1') # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
