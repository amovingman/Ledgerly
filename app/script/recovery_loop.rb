require 'fileutils'

running = true
%w[INT TERM].each { |signal| Signal.trap(signal) { running = false } }
FileUtils.mkdir_p(Rails.root.join('tmp'))
while running
  begin
    StripeIntegration::RecoverySweep.call
    Rails.root.join('tmp/recovery-heartbeat').write(Time.current.to_i.to_s)
  rescue ActiveRecord::ActiveRecordError, RedisClient::Error => e
    Rails.logger.warn("Stripe recovery sweep unavailable: #{e.class.name}")
  end
  sleep 15 if running
end
