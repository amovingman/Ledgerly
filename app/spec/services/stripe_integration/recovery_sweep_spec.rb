require 'rails_helper'

RSpec.describe StripeIntegration::RecoverySweep do
  before { configure_stripe_test }

  it 'dispatches committed work even when receipt-to-enqueue delivery was interrupted' do
    event = receive_stripe(stripe_payload(type: 'customer.updated'))
    expect(StripeIntegration::ProcessEventJob.jobs).to be_empty
    described_class.call
    expect(StripeIntegration::ProcessEventJob.jobs.size).to eq(1)
    expect(event.outbox_record.reload.dispatched_at).to be_present
  end

  it 'redelivers unfinished work after a queued job disappears' do
    event = receive_stripe(stripe_payload(type: 'customer.updated'))
    StripeIntegration::OutboxDispatcher.call
    StripeIntegration::ProcessEventJob.clear
    travel_to(6.minutes.from_now) { described_class.call }
    expect(StripeIntegration::ProcessEventJob.jobs.size).to eq(1)
    expect(event.reload.status).to eq('received')
  end

  it 'safely processes duplicate queued jobs after enqueue succeeded but dispatch marking failed' do
    invoice, gateway = paid_stripe_invoice
    event = receive_stripe(stripe_payload(object_id: invoice.stripe_invoice_id))
    record = event.outbox_record
    allow(OutboxRecord).to receive(:find).with(record.id).and_return(record)
    allow(record).to receive(:update!).and_raise('dispatch commit interrupted')
    expect { StripeIntegration::OutboxDispatcher.call }.to raise_error(RuntimeError, 'dispatch commit interrupted')
    allow(record).to receive(:update!).and_call_original
    StripeIntegration::OutboxDispatcher.call
    expect(StripeIntegration::ProcessEventJob.jobs.size).to eq(2)
    allow(StripeIntegration::Gateway).to receive(:new).and_return(gateway)
    StripeIntegration::ProcessEventJob.drain
    expect([StripePayment.count, event.reload.status]).to eq([1, 'processed'])
  end

  it 'does not requeue terminal receipts and closes pending terminal dispatch records' do
    event = receive_stripe(stripe_payload(type: 'customer.updated'))
    StripeIntegration::ProcessEvent.new(event: event).call
    described_class.call
    expect(StripeIntegration::ProcessEventJob.jobs).to be_empty
    expect(event.outbox_record.reload.dispatched_at).to be_present
  end

  it 'filters completed and recently attempted dispatched work before instantiating recovery records' do
    complete = receive_stripe(stripe_payload(type: 'customer.updated'))
    recent = receive_stripe(stripe_payload(type: 'customer.updated'))
    StripeIntegration::OutboxDispatcher.call
    complete.update!(status: 'processed')
    recent.update!(last_attempted_at: Time.current)
    [complete, recent].each { |event| event.outbox_record.update!(dispatched_at: 6.minutes.ago) }
    allow(described_class).to receive(:recover).and_call_original
    described_class.call
    expect(described_class).not_to have_received(:recover)
  end

  it 'recovers stale collection dispatches as well as event dispatches' do
    invoice = create_invoice
    invoice.ledger_transactions.create!(journal_attributes(invoice: invoice))
    collection = StripeIntegration::RequestCollection.call(invoice: invoice)
    StripeIntegration::OutboxDispatcher.call
    StripeIntegration::CollectInvoiceJob.clear
    collection.outbox_record.update!(dispatched_at: 6.minutes.ago)
    described_class.call
    expect(StripeIntegration::CollectInvoiceJob.jobs.size).to eq(1)
  end

  it 'manually replays a dead receipt without changing its raw event or effect identities' do
    event = receive_stripe(stripe_payload(type: 'customer.updated'))
    original = event.raw_payload
    event.update!(status: 'dead', attempts: 8, last_error: 'stripe_unavailable')
    described_class.replay(event)
    expect([event.reload.status, event.attempts, event.raw_payload]).to eq(['received', 0, original])
    expect(StripeIntegration::ProcessEventJob.jobs.size).to eq(1)
  end

  it 'rejects manual replays that would reset an in-progress retry budget' do
    event = receive_stripe(stripe_payload)
    expect { described_class.replay(event) }.to raise_error(Billing::Error) { |error| expect(error.code).to eq('not_replayable') }
  end

  it 'uses bounded jittered exponential delays and kills permanent review failures' do
    block = StripeIntegration::ProcessEventJob.sidekiq_retry_in_block
    transient = StripeIntegration::Retryable.new('stripe_unavailable')
    expect(block.call(0, transient, {})).to be_between(2, 5)
    expect(block.call(7, transient, {})).to be <= 300
    expect(block.call(0, StripeIntegration::ReviewRequired.new('identity_mismatch'), {})).to eq(:kill)
    expect(StripeIntegration::ProcessEventJob.get_sidekiq_options).to include('retry' => 7, 'dead' => true)
  end

  it 'records exhausted failures in PostgreSQL without regressing a completed receipt' do
    event = receive_stripe(stripe_payload(type: 'customer.updated'))
    job = { 'args' => [event.id] }
    StripeIntegration::RetryPolicy.exhausted(StripeEvent, job, StandardError.new)
    expect(event.reload.status).to eq('dead')
    described_class.replay(event)
    StripeIntegration::ProcessEvent.new(event: event).call
    StripeIntegration::RetryPolicy.exhausted(StripeEvent, job, StandardError.new)
    expect(event.reload.status).to eq('ignored')
  end
end
