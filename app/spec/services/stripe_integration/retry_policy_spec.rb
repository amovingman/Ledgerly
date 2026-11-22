require 'rails_helper'
require 'sidekiq/job_retry'
require 'sidekiq/api'

RSpec.describe StripeIntegration::RetryPolicy do
  before { configure_stripe_test }

  def with_dead_job(event, gateway)
    allow(StripeIntegration::Gateway).to receive(:new).and_return(gateway)
    jid = SecureRandom.hex(12)
    execute_failed_job(event, retry_payload(event, jid))
    yield Sidekiq::DeadSet.new.find_job(jid)
  ensure
    Sidekiq::DeadSet.new.find_job(jid)&.delete if jid
  end

  def retry_payload(event, jid)
    { 'class' => StripeIntegration::ProcessEventJob.name, 'args' => [event.id], 'queue' => 'webhooks',
      'jid' => jid, 'retry' => 7, 'dead' => true, 'created_at' => Time.current.to_f }
  end

  def execute_failed_job(event, payload)
    worker = StripeIntegration::ProcessEventJob.new
    handler = Sidekiq::JobRetry.new(Sidekiq.default_configuration)
    expect { handler.local(worker, JSON.generate(payload), 'webhooks') { worker.perform(event.id) } }
      .to raise_error(Sidekiq::JobRetry::Handled)
  end

  it 'places permanent review failures in the real Redis dead-job set' do
    invoice, gateway = paid_stripe_invoice
    gateway.objects['invoice'][invoice.stripe_invoice_id]['livemode'] = true
    event = receive_stripe(stripe_payload(object_id: invoice.stripe_invoice_id))
    with_dead_job(event, gateway) do |job|
      expect(job).to be_present
      expect(job.item.fetch('error_message')).to eq('remote_invoice_mismatch')
      expect(event.reload.status).to eq('review')
    end
  end

  it 'kills work after the persisted attempt budget is exhausted' do
    invoice, gateway = paid_stripe_invoice
    event = receive_stripe(stripe_payload(object_id: invoice.stripe_invoice_id))
    event.update!(attempts: 7)
    allow(gateway).to receive(:retrieve).and_raise(StripeIntegration::Retryable, 'stripe_unavailable')
    with_dead_job(event, gateway) do |job|
      expect(job).to be_present
      expect([event.reload.status, event.attempts]).to eq(['dead', 8])
      expect(StripePayment.count).to eq(0)
    end
  end
end
