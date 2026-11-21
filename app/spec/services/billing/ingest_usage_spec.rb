require 'rails_helper'

RSpec.describe Billing::IngestUsage do
  it 'returns the original event for a repeated key and normalized payload' do
    subscription = create_subscription
    first = ingest(subscription: subscription, key: 'same-key')
    replay = ingest(subscription: subscription, key: 'same-key', occurred_at: '2026-01-15T01:00:00+01:00')
    expect([first.replayed, replay.replayed, replay.record.id]).to eq([false, true, first.record.id])
    expect(UsageEvent.count).to eq(1)
  end

  it 'rejects a changed quantity without altering the original event' do
    subscription = create_subscription
    first = ingest(subscription: subscription, key: 'same-key')
    expect { ingest(subscription: subscription, key: 'same-key', quantity: 11) }
      .to raise_error(Billing::Error) { |error| expect(error.code).to eq('idempotency_conflict') }
    expect(first.record.reload.quantity).to eq(10)
  end

  it 'scopes keys to the customer across different subscriptions' do
    subscription = create_subscription
    other = create_subscription(customer: subscription.customer, plan: create_plan(metric: 'storage'))
    ingest(subscription: subscription, key: 'same-key')
    expect { ingest(subscription: other, key: 'same-key', metric: 'storage') }
      .to raise_error(Billing::Error) { |error| expect(error.code).to eq('idempotency_conflict') }
    expect(UsageEvent.count).to eq(1)
  end

  it 'allows the same key for distinct customers' do
    first = ingest(subscription: create_subscription, key: 'same-key')
    second = ingest(subscription: create_subscription, key: 'same-key')
    expect(first.record.id).not_to eq(second.record.id)
    expect(UsageEvent.count).to eq(2)
  end

  it 'returns an original result after cancellation and invoice issuance' do
    subscription = create_subscription
    first = ingest(subscription: subscription, key: 'same-key')
    Billing::Subscriptions.cancel(subscription: subscription)
    create_invoice(subscription: subscription)
    replay = ingest(subscription: subscription, key: 'same-key')
    expect(replay.record.id).to eq(first.record.id)
    expect(replay.replayed).to be(true)
  end

  it 'rejects new late usage after an invoice closes the period' do
    subscription = create_subscription
    create_invoice(subscription: subscription)
    expect { ingest(subscription: subscription) }
      .to raise_error(Billing::Error) { |error| expect(error.code).to eq('usage_period_closed') }
    expect(UsageEvent.count).to eq(0)
  end

  it 'includes the start and excludes the subscription end' do
    subscription = create_subscription(status: 'cancelled', ends_at: Time.utc(2026, 2, 1))
    accepted = ingest(subscription: subscription, occurred_at: '2026-01-01T00:00:00Z')
    expect(accepted.record.occurred_at).to eq(subscription.starts_at)
    expect { ingest(subscription: subscription, occurred_at: '2026-02-01T00:00:00Z') }
      .to raise_error(Billing::Error) { |error| expect(error.code).to eq('outside_subscription') }
  end

  it 'rejects future usage' do
    subscription = create_subscription
    travel_to(Time.utc(2026, 1, 10)) do
      expect { ingest(subscription: subscription) }
        .to raise_error(Billing::Error) { |error| expect(error.code).to eq('future_usage') }
    end
  end

  it 'rejects a mismatched metric' do
    expect { ingest(subscription: create_subscription, metric: 'storage') }
      .to raise_error(Billing::Error) { |error| expect(error.code).to eq('metric_mismatch') }
  end

  [0, -1, 1.5, '10', true, 1_000_000_001].each do |quantity|
    it "rejects invalid quantity #{quantity.inspect}" do
      expect { ingest(subscription: create_subscription, quantity: quantity) }
        .to raise_error(Billing::Error) { |error| expect(error.code).to eq('invalid_integer') }
    end
  end

  ['2026-02-31T00:00:00Z', '2026-01-15T00:00:00', '2026-01-15T00:00:00.1234567Z', 123].each do |timestamp|
    it "rejects invalid occurrence timestamp #{timestamp.inspect}" do
      expect { ingest(subscription: create_subscription, occurred_at: timestamp) }
        .to raise_error(Billing::Error) { |error| expect(error.code).to eq('invalid_timestamp') }
    end
  end

  [nil, '', 'spaces are invalid', 'a' * 129].each do |key|
    it "rejects an invalid key #{key.inspect}" do
      expect { ingest(subscription: create_subscription, key: key) }
        .to raise_error(Billing::Error) { |error| expect(error.code).to eq('invalid_idempotency_key') }
    end
  end
end
