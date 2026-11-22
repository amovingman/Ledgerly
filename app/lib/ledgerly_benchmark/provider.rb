require 'json'
require 'rack'
require_relative 'fixture'

module LedgerlyBenchmark
  class Provider
    def initialize
      @counts = Hash.new(0)
      @mutex = Mutex.new
    end

    def call(env)
      request = Rack::Request.new(env)
      return response(@mutex.synchronize { @counts.dup }) if request.path == '/_stats'

      @mutex.synchronize { @counts[request.request_method] += 1 }
      return response({ error: 'Benchmark provider forbids writes' }, 405) unless request.get?

      sleep 0.002 # Controlled minimum network-service time, identical in every run.
      kind, id = identify(request)
      return response({ error: 'Unknown fixture' }, 404) unless id && (1..Fixture::COUNT).cover?(id)

      object = resource(kind, id)
      object = { object: 'list', url: request.path, has_more: false, data: object } if object.is_a?(Array)
      response(object)
    end

    private

    def identify(request)
      path = request.path
      if %w[/v1/invoice_payments /v1/refunds].include?(path)
        params = request.params
        identity = params['invoice'] || params.dig('payment', 'payment_intent') || params['charge']
        [path.delete_prefix('/v1/'), identity.to_s[/\A(?:in|pi|ch)_bench_(\d+)\z/, 1]&.to_i]
      else
        match = %r{\A/v1/(invoices|payment_intents|charges)/(?:in|pi|ch)_bench_(\d+)\z}.match(path)
        match ? [match[1], match[2].to_i] : [nil, nil]
      end
    end

    def resource(kind, id)
      fixture = Fixture.attributes(id)
      common = { livemode: false, customer: "cus_bench_#{fixture.fetch(:customer_id)}",
                 currency: fixture.fetch(:currency) }
      amount = fixture.fetch(:amount)
      case kind
      when 'invoices'
        common.merge(id: "in_bench_#{id}", object: 'invoice', total: amount, amount_paid: amount,
                     status: 'paid', metadata: {})
      when 'payment_intents'
        common.merge(id: "pi_bench_#{id}", object: 'payment_intent', status: 'succeeded',
                     amount_received: amount, latest_charge: "ch_bench_#{id}")
      when 'charges'
        common.merge(id: "ch_bench_#{id}", object: 'charge', payment_intent: "pi_bench_#{id}",
                     paid: true, captured: true, amount_captured: amount)
      when 'invoice_payments'
        [common.merge(id: "inpay_bench_#{id}", object: 'invoice_payment', invoice: "in_bench_#{id}",
                      amount_paid: amount, status: 'paid',
                      payment: { type: 'payment_intent', payment_intent: "pi_bench_#{id}" })]
      when 'refunds'
        refund = Fixture.refund_amount(id)
        if refund.zero?
          []
        else
          [{ id: "re_bench_#{id}_0", object: 'refund', amount: refund,
             charge: "ch_bench_#{id}", currency: fixture.fetch(:currency), status: 'succeeded' }]
        end
      end
    end

    public :resource # Shared canonical fixture for the separate full-dataset service replay.

    def response(body, status = 200)
      [status, { 'content-type' => 'application/json' }, [JSON.generate(body)]]
    end
  end
end
