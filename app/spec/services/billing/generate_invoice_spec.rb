require 'rails_helper'

RSpec.describe Billing::GenerateInvoice do
  it 'atomically creates an invoice, snapshot, allocation and balanced issuance journal' do
    subscription = create_subscription
    event = create_usage(subscription: subscription)
    result = generate_invoice(subscription: subscription)
    invoice = result.record
    expect([invoice.amount, invoice.currency, result.replayed]).to eq([70, 'USD', false])
    expect(invoice.invoice_line_items.sole.attributes).to include('quantity' => 10, 'unit_amount' => 7, 'amount' => 70)
    expect(event.reload.invoice_line_item_id).to eq(invoice.invoice_line_items.sole.id)
    journal = invoice.ledger_transactions.sole
    expect(journal.ledger_entries.sum(:debit)).to eq(journal.ledger_entries.sum(:credit))
  end

  it 'returns the existing invoice without allocating or posting again' do
    subscription = create_subscription
    create_usage(subscription: subscription)
    first = generate_invoice(subscription: subscription)
    replay = generate_invoice(subscription: subscription)
    expect([replay.record.id, replay.replayed]).to eq([first.record.id, true])
    expect([Invoice.count, InvoiceLineItem.count, LedgerTransaction.count, LedgerEntry.count]).to eq([1, 1, 1, 2])
  end

  it 'includes the month start and final microsecond but excludes its end' do
    subscription = create_subscription
    first = create_usage(subscription: subscription, quantity: 1, occurred_at: Time.utc(2026, 1, 1))
    last = create_usage(subscription: subscription, quantity: 2,
                        occurred_at: Time.utc(2026, 1, 31, 23, 59, 59, 999_999))
    next_month = create_usage(subscription: subscription, quantity: 4, occurred_at: Time.utc(2026, 2, 1))
    january = generate_invoice(subscription: subscription).record
    expect(january.amount).to eq(21)
    expect([first.reload.invoice_line_item_id,
            last.reload.invoice_line_item_id]).to all(eq(january.invoice_line_items.sole.id))
    expect(next_month.reload.invoice_line_item_id).to be_nil
    february = generate_invoice(subscription: subscription, period_start: '2026-02-01T00:00:00Z').record
    expect(february.amount).to eq(28)
  end

  it 'keeps contract and invoice pricing stable after plan changes' do
    subscription = create_subscription
    create_usage(subscription: subscription)
    subscription.plan.update!(unit_amount: 99, currency: 'CAD')
    invoice = generate_invoice(subscription: subscription).record
    subscription.plan.update!(unit_amount: 111)
    expect([invoice.reload.amount, invoice.currency, invoice.invoice_line_items.sole.unit_amount]).to eq([70, 'USD', 7])
    expect { invoice.invoice_line_items.sole.update!(unit_amount: 999) }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'rolls back every effect when posting fails after allocation' do
    subscription = create_subscription
    event = create_usage(subscription: subscription)
    allow(Billing::PostIssuance).to receive(:call).and_raise(StandardError, 'injected posting failure')
    expect { generate_invoice(subscription: subscription) }.to raise_error(StandardError, 'injected posting failure')
    expect([Invoice.count, InvoiceLineItem.count, LedgerTransaction.count, LedgerEntry.count]).to eq([0, 0, 0, 0])
    expect(event.reload.invoice_line_item_id).to be_nil
  end

  it 'rejects empty periods and leaves them open for late usage' do
    subscription = create_subscription
    expect { generate_invoice(subscription: subscription) }
      .to raise_error(Billing::Error) { |error| expect(error.code).to eq('no_usage') }
    expect(Invoice.count).to eq(0)
    ingest(subscription: subscription)
    expect(generate_invoice(subscription: subscription).record.amount).to eq(70)
  end

  it 'rejects monetary overflow before creating any financial rows' do
    subscription = create_subscription(plan: create_plan(unit_amount: 1_000_000_000))
    10.times { create_usage(subscription: subscription, quantity: 1_000_000_000) }
    expect { generate_invoice(subscription: subscription) }
      .to raise_error(Billing::Error) { |error| expect(error.code).to eq('amount_out_of_range') }
    expect([Invoice.count, LedgerEntry.count, UsageEvent.where.not(invoice_line_item_id: nil).count]).to eq([0, 0, 0])
  end

  it 'issues a month exactly when its final boundary is reached' do
    subscription = create_subscription
    create_usage(subscription: subscription)
    travel_to(Time.utc(2026, 2, 1)) do
      expect(generate_invoice(subscription: subscription).record).to be_persisted
    end
  end

  it 'rejects an open month' do
    subscription = create_subscription
    travel_to(Time.utc(2026, 1, 31, 23, 59, 59)) do
      expect { generate_invoice(subscription: subscription) }
        .to raise_error(Billing::Error) { |error| expect(error.code).to eq('period_not_closed') }
    end
  end

  it 'requires an exact UTC month boundary' do
    expect { generate_invoice(subscription: create_subscription, period_start: '2026-01-01T00:00:00+01:00') }
      .to raise_error(Billing::Error) { |error| expect(error.code).to eq('invalid_period') }
  end

  it 'rejects a month outside the subscription active interval' do
    subscription = create_subscription(starts_at: Time.utc(2026, 3, 1))
    expect { generate_invoice(subscription: subscription) }
      .to raise_error(Billing::Error) { |error| expect(error.code).to eq('outside_subscription') }
  end
end
