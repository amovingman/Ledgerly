require 'rails_helper'

RSpec.describe LedgerlyBenchmark::Fixture do
  it 'spreads 50,000 unique subscription periods over the documented customer cohorts' do
    fixtures = (1..described_class::COUNT).map { |id| described_class.attributes(id) }
    customers = fixtures.group_by { |row| row.fetch(:customer_id) }.transform_values(&:size)
    expect(customers.values.tally).to eq({ 1000 => 10, 200 => 90, 25 => 400, 24 => 500 })
    expect(fixtures.map { |row| [row.fetch(:subscription_id), row.fetch(:month)] }.uniq.size).to eq(50_000)
    expect(fixtures.map { |row| row.fetch(:subscription_id) }.uniq.size).to eq(1460)
    expect(fixtures.all? { |row| row.fetch(:amount) == row.fetch(:quantity) * row.fetch(:unit_amount) }).to be(true)
  end

  it 'rejects identities outside the generated dataset' do
    expect { described_class.attributes(0) }.to raise_error(ArgumentError)
    expect { described_class.attributes(50_001) }.to raise_error(ArgumentError)
  end
end
