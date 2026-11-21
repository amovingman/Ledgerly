require_relative 'boot'

require 'rails'
require 'active_model/railtie'
require 'active_job/railtie'
require 'active_record/railtie'
require 'action_controller/railtie'

Bundler.require(*Rails.groups)

module Ledgerly
  class Application < Rails::Application
    config.load_defaults 8.1
    config.autoload_lib(ignore: %w[assets tasks])
    config.api_only = true
    config.time_zone = 'UTC'
    config.active_record.default_timezone = :utc
    config.active_job.queue_adapter = :sidekiq
    config.generators.test_framework :rspec
    config.debug_exception_response_format = :api
    config.exceptions_app = ->(env) { ApiExceptions.call(env) }
  end
end
