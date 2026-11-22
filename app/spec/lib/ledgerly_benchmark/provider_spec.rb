require 'rails_helper'

RSpec.describe LedgerlyBenchmark::Provider do
  subject(:provider) { Rack::MockRequest.new(described_class.new) }

  it 'returns matching full payment identities and both partial/full refund fixtures' do
    invoice = JSON.parse(provider.get('/v1/invoices/in_bench_2').body)
    partial = JSON.parse(provider.get('/v1/refunds?charge=ch_bench_2').body).fetch('data').first
    full = JSON.parse(provider.get('/v1/refunds?charge=ch_bench_3').body).fetch('data').first
    expect(invoice.values_at('livemode', 'status')).to eq([false, 'paid'])
    expect(partial.fetch('amount')).to eq(invoice.fetch('total') / 4)
    expect(full.fetch('amount')).to eq(LedgerlyBenchmark::Fixture.attributes(3).fetch(:amount))
  end

  it 'resolves the nested current InvoicePayment filter and refuses any provider writes' do
    path = '/v1/invoice_payments?payment[type]=payment_intent&payment[payment_intent]=pi_bench_1'
    allocation = JSON.parse(provider.get(path).body)
    expect(allocation.fetch('data').first.fetch('invoice')).to eq('in_bench_1')
    expect(provider.post('/v1/charges').status).to eq(405)
    expect(provider.get('/v1/invoices/in_bench_50001').status).to eq(404)
  end
end
