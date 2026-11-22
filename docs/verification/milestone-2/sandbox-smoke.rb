require 'net/http'
require 'json'

raise 'Expected a test sandbox' unless StripeIntegration::Settings.secret_key!.include?('_test_')
client = Stripe::StripeClient.new(StripeIntegration::Settings.secret_key!, stripe_version: StripeIntegration::Settings::API_VERSION)
# Sandbox-only verification; execute with the API, real worker and CLI listener running.
report = { api_version: StripeIntegration::Settings::API_VERSION, mode: 'sandbox', phases: [] }

def assert!(condition, message)
  raise message unless condition
end

def api(method, path, body = nil, headers = {})
  uri = URI('http://127.0.0.1:3000' + path)
  request = Net::HTTP.const_get(method.capitalize).new(uri)
  request['Authorization'] = 'Bearer ' + ENV.fetch('API_KEY')
  request['Content-Type'] = 'application/json'
  headers.each { |key, value| request[key] = value }
  request.body = JSON.generate(body) if body
  response = Net::HTTP.start(uri.host, uri.port, read_timeout: 15) { |http| http.request(request) }
  data = JSON.parse(response.body)
  raise "Local API rejected #{path}: #{response.code} #{data.dig('error', 'code')}" unless response.code.to_i.between?(200, 299)
  data
end

def wait_for(description)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 75
  loop do
    result = ActiveRecord::Base.uncached { yield }
    return result if result
    raise "Timed out: #{description}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    sleep 1
  end
end

begin
  run_id = ENV.fetch('STRIPE_SMOKE_RUN_ID') { SecureRandom.hex(6) }
  assert!(/\A[a-zA-Z0-9-]{1,40}\z/.match?(run_id), 'Invalid smoke run ID')
  email = "ledgerly-m2-#{run_id}@example.test"
  report[:run_id] = run_id
  customer = Customer.find_by(email: email)
  unless customer
    result = api('post', '/api/v1/customers', { customer: { name: 'Ledgerly sandbox acceptance', email: email } })
    customer = Customer.find(result.fetch('data').fetch('id'))
  end
  month = Time.current.utc.beginning_of_month.prev_month
  subscription = customer.subscriptions.first
  unless subscription
    plan = api('post', '/api/v1/plans', { plan: { name: 'Sandbox API calls', metric: 'api_calls', unit_amount: 7, currency: 'USD' } }).fetch('data')
    result = api('post', '/api/v1/subscriptions', { subscription: { customer_id: customer.id, plan_id: plan.fetch('id'), starts_at: month.iso8601 } })
    subscription = Subscription.find(result.fetch('data').fetch('id'))
  end
  api('post', '/api/v1/usage_events', { usage_event: { customer_id: customer.id, subscription_id: subscription.id, metric: 'api_calls', quantity: 10, occurred_at: (month + 1.day).iso8601 } }, { 'Idempotency-Key' => 'm2-real-sandbox-usage' })
  result = api('post', "/api/v1/subscriptions/#{subscription.id}/invoices", { invoice: { period_start: month.iso8601 } })
  invoice = Invoice.find(result.fetch('data').fetch('id'))
  assert!(invoice.amount == 70, 'Expected a 70-cent invoice')
  api('post', "/api/v1/invoices/#{invoice.id}/collection", {})
  collection = wait_for('collection') do
    record = invoice.reload.invoice_collection
    if record.terminal?
      raise "Collection stopped: #{record.status}/#{record.last_error}" unless record.status == 'succeeded'
      record
    end
  end
  invoice.reload
  customer.reload
  report.merge!(local_invoice_id: invoice.id, stripe_invoice_id: invoice.stripe_invoice_id, stripe_customer_id: customer.stripe_customer_id, amount: invoice.amount, currency: invoice.currency)
  report[:phases] << { name: 'collection', status: collection.status, attempts: collection.attempts, operation_count: invoice.stripe_operations.count }
  puts JSON.generate(report[:phases].last)
  $stdout.flush

  unless invoice.stripe_payment
    decline = client.v1.payment_methods.attach('pm_card_chargeCustomerFail', { customer: customer.stripe_customer_id }, { idempotency_key: "ledgerly:m2:decline-pm:#{invoice.id}" })
    begin
      client.v1.invoices.pay(invoice.stripe_invoice_id, { payment_method: decline.id }, { idempotency_key: "ledgerly:m2:decline-pay:#{invoice.id}" })
      raise 'Expected the test payment to decline'
    rescue Stripe::CardError => error
      assert!(error.code == 'card_declined', 'Unexpected decline code')
    end
    wait_for('failed webhook reconciliation') { invoice.reload.status == 'payment_failed' }
    report[:phases] << { name: 'failed_payment', local_status: invoice.status }
    puts JSON.generate(report[:phases].last)
    $stdout.flush
    visa = client.v1.payment_methods.attach('pm_card_visa', { customer: customer.stripe_customer_id }, { idempotency_key: "ledgerly:m2:visa-pm:#{invoice.id}" })
    client.v1.invoices.pay(invoice.stripe_invoice_id, { payment_method: visa.id }, { idempotency_key: "ledgerly:m2:successful-pay:#{invoice.id}" })
  end
  payment = wait_for('paid webhook reconciliation') { invoice.reload.stripe_payment }
  report[:phases] << { name: 'successful_payment', local_status: invoice.reload.status, charge_id: payment.charge_id, payment_intent_id: payment.payment_intent_id }
  puts JSON.generate(report[:phases].last)
  $stdout.flush

  [20, 50].each_with_index do |amount, index|
    refund = client.v1.refunds.create({ charge: payment.charge_id, amount: amount }, { idempotency_key: "ledgerly:m2:refund:#{invoice.id}:#{index}" })
    wait_for('refund webhook reconciliation') { StripeRefund.exists?(stripe_id: refund.id) }
    report[:phases] << { name: 'refund', stripe_id: refund.id, amount: amount, local_status: invoice.reload.status }
    puts JSON.generate(report[:phases].last)
    $stdout.flush
  end

  events = StripeEvent.where("payload #>> '{data,object,id}' IN (?)", [invoice.stripe_invoice_id, payment.charge_id]).order(:id).to_a
  assert!(events.map(&:event_type).uniq.sort == %w[charge.refunded invoice.paid invoice.payment_failed], 'Missing actual Stripe webhook types')
  wait_for('all original events processed') { events.all? { |event| event.reload.status == 'processed' } }
  replay_count = 0
  3.times do
    events.reverse_each do |event|
      raw = event.raw_payload
      stamp = Time.current
      digest = Stripe::Webhook::Signature.compute_signature(stamp, raw, StripeIntegration::Settings.webhook_secret!)
      signature = Stripe::Webhook::Signature.generate_header(stamp, digest)
      uri = URI('http://127.0.0.1:3000/webhooks/stripe')
      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      request['Stripe-Signature'] = signature
      request.body = raw
      response = Net::HTTP.start(uri.host, uri.port) { |http| http.request(request) }
      assert!(response.code == '200' && JSON.parse(response.body)['duplicate'], 'Replay was not deduplicated')
      replay_count += 1
    end
  end
  sleep 2
  journals = invoice.ledger_transactions.includes(:ledger_entries)
  entries = journals.flat_map(&:ledger_entries)
  charges = client.v1.charges.list(customer: customer.stripe_customer_id, limit: 100).auto_paging_each.to_a
  captured = charges.select { |charge| charge.paid && charge.captured }
  assert!(captured.size == 1 && captured.first.amount_captured == 70, 'Expected exactly one successful captured charge')
  assert!(captured.first.amount_refunded == 70, 'Expected full refund')
  assert!(StripePayment.where(invoice: invoice).count == 1, 'Duplicate local payment')
  assert!(payment.stripe_refunds.count == 2 && payment.stripe_refunds.sum(:amount) == 70, 'Refund effect mismatch')
  assert!(journals.count == 4 && entries.size == 8, 'Journal effect count mismatch')
  assert!(journals.all? { |journal| journal.ledger_entries.sum(&:debit) == journal.ledger_entries.sum(&:credit) }, 'Unbalanced journal')
  balance = api('get', "/api/v1/customers/#{customer.id}/balance").fetch('data').fetch('balances')
  assert!(balance == [{ 'currency' => 'USD', 'amount' => 0 }], 'Receivable balance mismatch')
  assert!(invoice.reload.status == 'refunded', 'Expected fully refunded local invoice')
  report.merge!(passed: true, completed_at: Time.current.iso8601, real_stripe_events: events.map { |event| { id: event.stripe_id, type: event.event_type, status: event.status } }, reverse_order_duplicate_replays: replay_count, local_payment_count: 1, local_refund_count: 2, journal_count: journals.count, ledger_row_count: entries.size, total_debits: entries.sum(&:debit), total_credits: entries.sum(&:credit), successful_captured_charge_count: captured.size, declined_charge_count: charges.count { |charge| !charge.paid }, captured_amount: captured.first.amount_captured, refunded_amount: captured.first.amount_refunded, receivable_balances: balance, final_invoice_status: invoice.status)
  puts 'LEDGERLY_SANDBOX_REPORT=' + JSON.generate(report)
rescue => error
  failure = { passed: false, error_class: error.class.name, phases: report[:phases] }
  if error.is_a?(Stripe::StripeError)
    failure[:provider_code] = error.code
    failure[:provider_message] = error.message
  else
    failure[:message] = error.message
  end
  puts JSON.generate(failure)
  raise
end
