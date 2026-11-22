require 'rails_helper'

RSpec.describe LedgerlyBenchmark::Safety do
  it 'rejects the ordinary test environment even if a benchmark database name is supplied' do
    expect { described_class.check! }.to raise_error(RuntimeError, /dedicated benchmark environment/)
  end

  it 'refuses inherited database URLs even with the dedicated environment and fixture keys' do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('benchmark'))
    stub_const('ENV', ENV.to_h.merge('DB_HOST' => 'benchmark-postgres',
                                     'REDIS_URL' => 'redis://benchmark-redis:6379/0',
                                     'STRIPE_SECRET_KEY' => 'sk_test_benchmark',
                                     'STRIPE_WEBHOOK_SECRET' => 'whsec_benchmark',
                                     'DATABASE_URL' => 'postgresql://elsewhere/ledgerly_development'))
    expect { described_class.check! }.to raise_error(RuntimeError, /must not override/)
  end
end
