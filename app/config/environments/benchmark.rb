# Isolated local measurements, using production-style eager loading without TLS redirects.
Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.force_ssl = false
  config.assume_ssl = false
  config.cache_store = :null_store
  config.log_level = :warn
  config.logger = ActiveSupport::TaggedLogging.logger($stdout)
  config.active_support.report_deprecations = false
  config.active_record.dump_schema_after_migration = false
end
