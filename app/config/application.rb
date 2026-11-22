require_relative 'boot'

require 'rails'
require 'active_model/railtie'
require 'active_job/railtie'
require 'active_record/railtie'
require 'action_controller/railtie'
require 'action_view/railtie'

Bundler.require(*Rails.groups)

module Ledgerly
  class Application < Rails::Application
    config.load_defaults 8.1
    config.autoload_lib(ignore: %w[assets tasks])
    config.api_only = true
    config.public_file_server.headers = { 'cache-control' => 'no-cache' }
    config.session_store :cookie_store, key: '_ledgerly_dashboard', same_site: :strict,
                                        httponly: true, secure: Rails.env.production?, expire_after: 30.minutes
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use config.session_store, config.session_options
    config.time_zone = 'UTC'
    config.active_record.default_timezone = :utc
    config.active_job.queue_adapter = :sidekiq
    config.generators.test_framework :rspec
    config.debug_exception_response_format = :api
    config.exceptions_app = ->(env) { ApiExceptions.call(env) }
  end
end
