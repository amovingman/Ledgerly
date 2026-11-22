require 'rails_helper'

RSpec.describe LedgerlyBenchmark::Verify, :concurrency do
  self.use_transactional_tests = false

  around do |example|
    clean_billing_data
    example.run
  ensure
    clean_billing_data
  end

  it 'checks fresh committed effects even when its observer has an older SQL cache' do
    stub_const('LedgerlyBenchmark::Verify::COUNTS', { customers: 0 })
    stub_const('LedgerlyBenchmark::Verify::CHECKS', {})
    allow(described_class).to receive(:verify_samples!)
    connection = ActiveRecord::Base.connection
    ActiveRecord::Base.cache do
      expect(described_class.call[:financial_counts]['stripe_events']).to eq(0)
      expect(connection.select_value('SELECT count(*) FROM stripe_events')).to eq(0)
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          StripeEvent.create!(stripe_id: 'evt_fresh_observer', event_type: 'customer.updated', api_version: 'fixture',
                              raw_payload: '{}', payload: {})
        end
      end.value
      expect(connection.select_value('SELECT count(*) FROM stripe_events')).to eq(0)
      expect(described_class.call[:financial_counts]['stripe_events']).to eq(1)
    end
  end
end
