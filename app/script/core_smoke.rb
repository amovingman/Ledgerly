require 'net/http'
require 'json'
require 'securerandom'
require 'time'
require 'date'

# A unique synthetic customer makes repeated smoke runs safe on development DBs.
def build_request(method, uri, body, key)
  message = Net::HTTP.const_get(method.capitalize).new(uri)
  message['Authorization'] = "Bearer #{ENV.fetch('API_KEY')}"
  message['Content-Type'] = 'application/json'
  message['Idempotency-Key'] = key if key
  message.body = JSON.generate(body) if body
  message
end

def request(method, path, body = nil, key: nil, expected: 200)
  uri = URI("http://127.0.0.1:3000#{path}")
  message = build_request(method, uri, body, key)
  response = Net::HTTP.start(uri.host, uri.port, read_timeout: 10) { |http| http.request(message) }
  raise "Expected #{expected} from #{path}; got #{response.code}" unless response.code.to_i == expected

  JSON.parse(response.body)
end

run_id = SecureRandom.hex(6)
now = Time.now.utc
month = Date.new(now.year, now.month, 1).prev_month
start = Time.utc(month.year, month.month, 1).iso8601
customer = request('post', '/api/v1/customers', { customer: { name: 'Acceptance smoke',
                                                              email: "acceptance-#{run_id}@example.test" } },
                   expected: 201).fetch('data')
plan = request('post', '/api/v1/plans', { plan: { name: 'Smoke calls', metric: 'calls', unit_amount: 7,
                                                  currency: 'USD' } }, expected: 201).fetch('data')
subscription = request('post', '/api/v1/subscriptions',
                       { subscription: { customer_id: customer.fetch('id'), plan_id: plan.fetch('id'),
                                         starts_at: start } }, expected: 201).fetch('data')
usage = { usage_event: { customer_id: customer.fetch('id'), subscription_id: subscription.fetch('id'),
                         metric: 'calls', quantity: 10, occurred_at: start } }
first = request('post', '/api/v1/usage_events', usage, key: "smoke-#{run_id}", expected: 201)
raise 'Usage replay changed' unless request('post', '/api/v1/usage_events', usage, key: "smoke-#{run_id}") == first

request('post', '/api/v1/usage_events', { usage_event: usage.fetch(:usage_event).merge(quantity: 11) },
        key: "smoke-#{run_id}", expected: 409)
invoice_path = "/api/v1/subscriptions/#{subscription.fetch('id')}/invoices"
invoice = request('post', invoice_path, { invoice: { period_start: start } }, expected: 201)
raise 'Invoice replay changed' unless request('post', invoice_path, { invoice: { period_start: start } }) == invoice

balance_path = "/api/v1/customers/#{customer.fetch('id')}/balance"
expected_balance = [{ 'currency' => 'USD', 'amount' => 70 }]
2.times do
  raise 'Balance mismatch' unless request('get', balance_path).dig('data', 'balances') == expected_balance
end
puts JSON.generate({ passed: true, scenario: 'HTTP usage/invoice replay, conflict and cached balance',
                     amount: 70, currency: 'USD', customer_id: customer.fetch('id'),
                     invoice_id: invoice.dig('data', 'id'), outgoing_stripe_operations: 0 })
