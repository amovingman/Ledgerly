require 'simplecov'
SimpleCov.start do
  skip '/spec/'
  cover 'app/**/*.rb'
  enable_coverage :branch
  minimum_coverage line: 90, branch: 80
end

RSpec.configure do |config|
  config.expect_with(:rspec) { |expectations| expectations.include_chain_clauses_in_custom_matcher_descriptions = true }
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
