# Refuse destructive test setup against a development or production database.
if Rails.env.test?
  config = ActiveRecord::Base.configurations.configs_for(env_name: 'test', name: 'primary')
  raise 'Test database name must end in _test or _test_<number>.' unless /_test(?:_\d+)?\z/.match?(config.database.to_s)
end
