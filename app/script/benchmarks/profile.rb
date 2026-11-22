require Rails.root.join('lib/ledgerly_benchmark/safety')
LedgerlyBenchmark::Safety.check!
report = { sql: {}, gateway: {}, phases: {} }
phase = nil
subscription = ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, start, finish, _id, payload|
  next unless phase && payload[:name] != 'SCHEMA'

  stats = (report[:sql][phase] ||= { queries: 0, milliseconds: 0.0, examples: [] })
  stats[:queries] += 1
  stats[:milliseconds] += (finish - start) * 1000
  stats[:examples] << payload[:sql] if stats[:examples].size < 8
end
measure = lambda do |name, &block|
  phase = name
  puts "PROFILE_START=#{name}"
  $stdout.flush
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  cpu = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
  block.call
  report[:phases][name] = { seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - start,
                            cpu_seconds: Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) - cpu }
  phase = nil
end
measure.call('recovery_sweep') { StripeIntegration::RecoverySweep.call }
gateway = StripeIntegration::Gateway.new
%i[retrieve list].each do |method|
  original = gateway.method(method)
  gateway.define_singleton_method(method) do |*args|
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    begin
      original.call(*args)
    ensure
      key = "#{method}:#{args.first}"
      values = (report[:gateway][key] ||= [])
      values << ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000)
    end
  end
end
measure.call('reconcile_20_payments') do
  [1, *Array.new(19) { |i| (i + 1) * 10 }].each do |id|
    payload = { id: "evt_profile_#{id}", object: 'event', livemode: false, type: 'invoice.paid',
                api_version: StripeIntegration::Settings::API_VERSION,
                data: { object: { id: "in_bench_#{id}", object: 'invoice' } } }
    raw = JSON.generate(payload)
    time = Time.current
    digest = Stripe::Webhook::Signature.compute_signature(time, raw, StripeIntegration::Settings.webhook_secret!)
    signature = Stripe::Webhook::Signature.generate_header(time, digest)
    event = StripeIntegration::ReceiveEvent.call(raw: raw, signature: signature).record
    StripeIntegration::ProcessEvent.new(event: event, gateway: gateway).call
  end
end
ActiveSupport::Notifications.unsubscribe(subscription)
report[:gateway].transform_values! do |values|
  { count: values.size, mean_ms: values.sum / values.size, max_ms: values.max, total_ms: values.sum }
end
puts "LEDGERLY_PROFILE=#{JSON.generate(report)}"
