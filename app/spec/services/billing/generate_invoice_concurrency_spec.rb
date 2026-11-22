require 'rails_helper'
require 'concurrent'

RSpec.describe Billing::GenerateInvoice, :concurrency do
  self.use_transactional_tests = false

  around do |example|
    clean_committed_data
    example.run
  ensure
    clean_committed_data
  end

  def clean_committed_data
    [LedgerEntry, LedgerTransaction, UsageEvent, InvoiceLineItem, Invoice, Subscription, Plan,
     Customer].each(&:delete_all)
  end

  def concurrently(count = 4, &)
    barrier = Concurrent::CyclicBarrier.new(count)
    threads = Array.new(count) { |index| concurrent_worker(barrier, index, &) }
    threads.map(&:value)
  ensure
    threads&.each(&:join)
  end

  def concurrent_worker(barrier, index)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        raise 'Concurrency barrier timed out' unless barrier.wait(10)

        yield(index)
      end
    end
  end

  it 'stores one usage event under simultaneous duplicate requests' do
    subscription = create_subscription
    results = concurrently do
      ingest(subscription: Subscription.find(subscription.id), key: 'concurrent-key')
    end
    expect(results.map { |result| result.record.id }.uniq.size).to eq(1)
    expect(results.count(&:replayed)).to eq(3)
    expect(UsageEvent.count).to eq(1)
  end

  it 'creates one invoice, allocation and balanced journal under simultaneous generation' do
    subscription = create_subscription
    ingest(subscription: subscription)
    results = concurrently { generate_invoice(subscription: Subscription.find(subscription.id)) }
    expect(results.map { |result| result.record.id }.uniq.size).to eq(1)
    expect(results.count(&:replayed)).to eq(3)
    expect([Invoice.count, InvoiceLineItem.count, LedgerTransaction.count, LedgerEntry.count]).to eq([1, 1, 1, 2])
    expect(UsageEvent.sole.invoice_line_item_id).to eq(InvoiceLineItem.sole.id)
    expect(LedgerEntry.sum(:debit)).to eq(LedgerEntry.sum(:credit))
  end

  # Keep the competing operations and both permitted outcomes together.
  # rubocop:disable RSpec/ExampleLength
  it 'either includes racing usage in the invoice or explicitly rejects it as closed' do
    subscription = create_subscription
    ingest(subscription: subscription, key: 'base')
    results = concurrently(2) do |index|
      current = Subscription.find(subscription.id)
      if index.zero?
        begin
          ingest(subscription: current, key: 'racing-usage', quantity: 3)
        rescue Billing::Error => e
          e
        end
      else
        generate_invoice(subscription: current)
      end
    end
    usage_result = results.first
    expected_quantity = usage_result.is_a?(Billing::Error) ? 10 : 13
    expect(usage_result.code).to eq('usage_period_closed') if usage_result.is_a?(Billing::Error)
    expect(InvoiceLineItem.sole.quantity).to eq(expected_quantity)
    expect(Invoice.sole.amount).to eq(expected_quantity * subscription.unit_amount)
    expect(UsageEvent.where(invoice_line_item_id: nil).count).to eq(0)
  end

  # rubocop:enable RSpec/ExampleLength

  it 'accepts exactly one overlapping subscription under simultaneous creation' do
    customer = create_customer
    plan = create_plan
    results = concurrently do
      Billing::Subscriptions.create(customer: Customer.find(customer.id), plan: Plan.find(plan.id),
                                    starts_at: '2026-01-01T00:00:00Z')
    rescue Billing::Error => e
      e
    end
    expect(results.count { |result| result.is_a?(Subscription) }).to eq(1)
    expect(results.grep(Billing::Error).map(&:code)).to eq(['subscription_overlap'] * 3)
    expect(Subscription.count).to eq(1)
  end
end
