require Rails.root.join('lib/ledgerly_benchmark/safety')
LedgerlyBenchmark::Safety.check!

module SustainedProfile
  def self.results
    @results ||= Hash.new { |hash, name| hash[name] = { calls: 0, wall_seconds: 0.0, cpu_seconds: 0.0, sql: 0 } }
  end

  def self.measure(name)
    (Thread.current[:sustained_profile] ||= []) << name
    wall = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    cpu = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
    yield
  ensure
    record(name, wall, cpu)
    Thread.current[:sustained_profile].pop
  end

  def self.record(name, wall, cpu)
    row = results[name]
    row[:calls] += 1
    row[:wall_seconds] += Process.clock_gettime(Process::CLOCK_MONOTONIC) - wall
    row[:cpu_seconds] += Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) - cpu
  end

  def self.wrap(klass, method)
    klass.prepend(Module.new do
      define_method(method) do |*args, **kwargs, &block|
        SustainedProfile.measure("#{self.class.name}##{method}") { super(*args, **kwargs, &block) }
      end
    end)
  end
end

[StripeIntegration::ProcessEvent, StripeIntegration::ResolveSnapshot, StripeIntegration::PostEffects].each do |klass|
  SustainedProfile.wrap(klass, :call)
end
%i[post_payment post_journal update_status].each { |method| SustainedProfile.wrap(StripeIntegration::PostEffects, method) }
%i[retrieve list].each { |method| SustainedProfile.wrap(StripeIntegration::Gateway, method) }
SustainedProfile.wrap(ApplicationRecord, :valid?)
subscription = ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, _start, _finish, _id, payload|
  next if payload[:name] == 'SCHEMA' || payload[:cached]

  Thread.current[:sustained_profile]&.each { |name| SustainedProfile.results[name][:sql] += 1 }
end
GC::Profiler.enable
initial_gc = GC.stat
count = Integer(ENV.fetch('PROFILE_PAYMENTS', '200'))
count.times do |index|
  id = index.zero? ? 1 : index * 10
  raise 'Profile needs fresh payments' if StripePayment.exists?(invoice_id: id)

  payload = { id: "evt_sustained_profile_#{id}", object: 'event', type: 'invoice.paid', livemode: false,
              api_version: StripeIntegration::Settings::API_VERSION,
              data: { object: { id: "in_bench_#{id}", object: 'invoice' } } }
  raw = JSON.generate(payload)
  stamp = Time.current
  digest = Stripe::Webhook::Signature.compute_signature(stamp, raw, StripeIntegration::Settings.webhook_secret!)
  signature = Stripe::Webhook::Signature.generate_header(stamp, digest)
  event = SustainedProfile.measure('receipt') { StripeIntegration::ReceiveEvent.call(raw: raw, signature: signature).record }
  StripeIntegration::ProcessEvent.new(event: event).call
end
ActiveSupport::Notifications.unsubscribe(subscription)
report = { payments: count, stages: SustainedProfile.results, gc_seconds: GC::Profiler.total_time,
           initial_gc: initial_gc, final_gc: GC.stat,
           note: 'Sequential real SDK/local HTTP; inclusive nested timings; diagnostic only.' }
puts "SUSTAINED_PROFILE=#{JSON.generate(report)}"
