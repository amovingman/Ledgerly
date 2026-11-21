require 'rails_helper'

RSpec.describe Billing::Subscriptions do
  it 'snapshots plan pricing and normalizes an explicit start to UTC' do
    plan = create_plan
    subscription = described_class.create(customer: create_customer, plan: plan, starts_at: '2026-01-01T01:00:00+01:00')
    plan.update!(unit_amount: 99, currency: 'CAD')
    expect([subscription.reload.unit_amount, subscription.currency, subscription.metric]).to eq([7, 'USD', 'api_calls'])
    expect(subscription.starts_at).to eq(Time.utc(2026, 1, 1))
  end

  it 'defaults a new contract to the current time' do
    travel_to Time.utc(2026, 3, 1) do
      subscription = described_class.create(customer: create_customer, plan: create_plan)
      expect(subscription.starts_at).to eq(Time.current)
    end
  end

  it 'turns overlap violations into a recoverable conflict' do
    subscription = create_subscription
    expect do
      described_class.create(customer: subscription.customer, plan: create_plan, starts_at: '2026-01-01T00:00:00Z')
    end.to raise_error(Billing::Error) { |error| expect(error.code).to eq('subscription_overlap') }
  end

  it 'rejects invalid calendar timestamps' do
    expect do
      described_class.create(customer: create_customer, plan: create_plan, starts_at: '2026-02-31T00:00:00Z')
    end.to raise_error(Billing::Error) { |error| expect(error.code).to eq('invalid_timestamp') }
  end

  it 'cancels at the current time and preserves that timestamp on replay' do
    subscription = create_subscription
    travel_to(Time.utc(2026, 2, 1)) { described_class.cancel(subscription: subscription) }
    travel_to(Time.utc(2026, 3, 1)) { described_class.cancel(subscription: subscription) }
    expect(subscription.reload.ends_at).to eq(Time.utc(2026, 2, 1))
    expect(subscription.status).to eq('cancelled')
  end

  it 'cancels a future subscription as an empty interval' do
    subscription = create_subscription(starts_at: Time.utc(2027, 1, 1))
    travel_to(Time.utc(2026, 2, 1)) { described_class.cancel(subscription: subscription) }
    expect(subscription.reload.ends_at).to eq(subscription.starts_at)
  end
end
