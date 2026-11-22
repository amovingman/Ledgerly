require 'rails_helper'
require 'timeout'

RSpec.describe Billing::ReadCache, :concurrency do
  self.use_transactional_tests = false

  let(:redis) { Redis.new(url: ENV.fetch('REDIS_URL')) }

  around do |example|
    clean_billing_data
    example.run
  ensure
    redis.scan_each(match: 'ledgerly:reads:v1:*').each { |key| redis.del(key) }
    clean_billing_data
  end

  before do
    configure_stripe_test
    stub_const('ENV', ENV.to_h.merge('READ_CACHE_ENABLED' => '1'))
    described_class.instance_variable_set(:@retry_after, nil)
    allow(described_class).to receive(:client).and_return(redis)
  end

  def issued
    subscription = create_subscription
    create_usage(subscription: subscription)
    invoice = generate_invoice(subscription: subscription).record
    [invoice, subscription]
  end

  def issue_next(subscription)
    create_usage(subscription: subscription, quantity: 20, occurred_at: Time.utc(2026, 2, 15))
    generate_invoice(subscription: subscription, period_start: '2026-02-01T00:00:00Z')
  end

  it 'reuses a bounded, expiring serialized balance' do
    invoice, = issued
    allow(Billing::CustomerBalance).to receive(:calculate).and_call_original
    2.times { expect(Billing::CustomerBalance.call(customer: invoice.customer)).to eq([{ currency: 'USD', amount: 70 }]) }
    expect(Billing::CustomerBalance).to have_received(:calculate).once
    key = redis.scan_each(match: 'ledgerly:reads:v1:*').first
    expect(redis.ttl(key)).to be_between(1, described_class::TTL)
  end

  it 'invalidates committed invoice/ledger changes even with an old customer object' do
    invoice, subscription = issued
    customer = invoice.customer
    expect(Billing::CustomerBalance.call(customer: customer).first[:amount]).to eq(70)
    issue_next(subscription)
    expect(Billing::CustomerBalance.call(customer: customer).first[:amount]).to eq(210)
  end

  it 'bypasses cached values inside a write transaction and preserves old reads after rollback' do
    invoice, = issued
    customer = invoice.customer
    expect(Billing::CustomerBalance.call(customer: customer).first[:amount]).to eq(70)
    version = customer.reload.read_version
    ApplicationRecord.transaction do
      post_test_payment(invoice)
      expect(Billing::CustomerBalance.call(customer: customer).first[:amount]).to eq(0)
      raise ActiveRecord::Rollback
    end
    expect(customer.reload.read_version).to eq(version)
    expect(Billing::CustomerBalance.call(customer: customer).first[:amount]).to eq(70)
  end

  def post_test_payment(invoice)
    attributes = journal_attributes(invoice: invoice).merge(journal_type: 'payment',
                                                            business_effect_key: 'cache:payment')
    attributes[:ledger_entries] = [LedgerEntry.new(account: 'stripe_clearing', debit: 70),
                                   LedgerEntry.new(account: 'accounts_receivable', credit: 70)]
    LedgerTransaction.create!(attributes)
  end

  it 'keeps a late cache fill from poisoning the version committed by a concurrent writer' do
    invoice, subscription = issued
    ready = Queue.new
    release = Queue.new
    thread = late_reader(invoice.customer, ready, release)
    Timeout.timeout(5) { ready.pop }
    issue_next(subscription)
    release << true
    expect(thread.value).to eq([{ currency: 'USD', amount: 70 }])
    expect(Billing::CustomerBalance.call(customer: invoice.customer).first[:amount]).to eq(210)
  ensure
    release << true if release
    thread&.join(5)
  end

  def late_reader(customer, ready, release)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        described_class.fetch(customer: customer, key: 'balance') do
          value = Billing::CustomerBalance.send(:calculate, customer)
          ready << true
          release.pop
          value
        end
      end
    end
  end

  it 'does not fill a new version from an old Active Record query-cache snapshot' do
    invoice, subscription = issued
    ActiveRecord::Base.cache do
      expect(Billing::CustomerBalance.send(:calculate, invoice.customer).first[:amount]).to eq(70)
      thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { issue_next(subscription) }
      end
      thread.value
      expect(Billing::CustomerBalance.send(:calculate, invoice.customer).first[:amount]).to eq(70)
      expect(Billing::CustomerBalance.call(customer: invoice.customer).first[:amount]).to eq(210)
    end
  end

  it 'falls back to the database when Redis reads fail and temporarily avoids repeated connection attempts' do
    invoice, = issued
    allow(redis).to receive(:get).and_raise(Redis::CannotConnectError)
    2.times { expect(Billing::CustomerBalance.call(customer: invoice.customer).first[:amount]).to eq(70) }
    expect(redis).to have_received(:get).once
  end

  it 'returns the computed value even when writing the cache fails' do
    invoice, = issued
    allow(redis).to receive(:set).and_raise(Redis::CannotConnectError)
    expect(Billing::CustomerBalance.call(customer: invoice.customer).first[:amount]).to eq(70)
  end

  it 'recovers from malformed cached JSON without using it as a balance' do
    invoice, = issued
    version = invoice.customer.reload.read_version
    redis.set("ledgerly:reads:v1:#{invoice.customer_id}:#{version}:balance", 'not json', ex: 30)
    expect(Billing::CustomerBalance.call(customer: invoice.customer).first[:amount]).to eq(70)
  end

  it 'does not store oversized payloads or uncached page requests' do
    customer = create_customer
    expect(described_class.fetch(customer: customer, key: 'large') { 'x' * 70_000 }).to have_attributes(size: 70_000)
    described_class.fetch(customer: customer, key: 'deep', cacheable: false) { 'uncached' }
    expect(redis.scan_each(match: "ledgerly:reads:v1:#{customer.id}:*").to_a).to be_empty
  end
end
