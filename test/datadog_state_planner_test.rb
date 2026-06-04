# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/slo_rules_engine'

class DatadogStatePlannerTest < Minitest::Test
  def setup
    SloRulesEngine.clear_definitions
    load File.expand_path('../examples/services/checkout.rb', __dir__)
    definition = SloRulesEngine.definitions.fetch(0)
    @manifest = SloRulesEngine.default_provider_registry.fetch('datadog')
      .generate(definition)
      .to_h
      .merge(service: definition.service)
  end

  def test_builds_desired_state_and_create_plan_operations
    planner = SloRulesEngine::Datadog::StatePlanner.new

    desired = planner.desired_state(@manifest)
    operations = planner.plan_operations(@manifest, state: {})

    assert_equal [
      { name: @manifest.fetch(:artifacts).fetch(:slos).fetch(0).fetch(:name), source: 'artifacts.slos[0]' }
    ], desired.fetch(:slos)
    assert_equal %w[create_and_wait create create create], operations.map(&:action)
    assert_equal [
      'artifacts.slos[0]',
      'artifacts.monitors[0]',
      'artifacts.telemetry_gap_monitors[0]',
      'artifacts.dashboards[0]'
    ], operations.map(&:source)
  end
end
