# frozen_string_literal: true

if ENV["COVERAGE"].to_s != ""
  require "simplecov"

  SimpleCov.start "rails" do
    enable_coverage :branch
    add_filter "/spec/"
  end
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "tmp/examples.txt"
  config.order = :random
  Kernel.srand config.seed
end
