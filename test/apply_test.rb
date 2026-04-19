# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/slo_rules_engine'

class ApplyTest < Minitest::Test
  def test_apply_plan_serializes_operations
    operation = SloRulesEngine::ApplyOperation.new(
      action: 'create',
      target: 'datadog.slo',
      name: 'checkout-api successful requests',
      source: 'artifacts.slos[0]',
      payload: { name: 'checkout-api successful requests' }
    )
    plan = SloRulesEngine::ApplyPlan.new(provider: 'datadog', mode: 'dry_run', operations: [operation])

    payload = plan.to_h

    assert_equal 'datadog', payload.fetch(:provider)
    assert_equal 'dry_run', payload.fetch(:mode)
    assert_equal 'create', payload.fetch(:operations).fetch(0).fetch(:action)
    assert_equal 'datadog.slo', payload.fetch(:operations).fetch(0).fetch(:target)
    assert_equal 'artifacts.slos[0]', payload.fetch(:operations).fetch(0).fetch(:source)
  end

  def test_apply_plan_knows_when_it_is_empty
    plan = SloRulesEngine::ApplyPlan.new(provider: 'datadog', mode: 'dry_run', operations: [])

    assert plan.empty?
  end

  def test_manifest_bundle_applier_plans_manifest_write
    manifest = { provider: 'prometheus_stack', service: 'checkout-api', artifacts: { recording_rules: [] } }
    applier = SloRulesEngine::Appliers::ManifestBundle.new(output_dir: '/tmp/generated')

    plan = applier.plan(manifest)

    assert_equal 'prometheus_stack', plan.provider
    assert_equal 'dry_run', plan.mode
    assert_equal 'write', plan.operations.fetch(0).action
    assert_equal 'manifest_file', plan.operations.fetch(0).target
    assert_equal '/tmp/generated/checkout-api/prometheus_stack/manifest.json', plan.operations.fetch(0).payload.fetch(:path)
  end
end
