# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/slo_rules_engine'
require 'tmpdir'

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
    manifest = valid_prometheus_manifest
    applier = SloRulesEngine::Appliers::ManifestBundle.new(output_dir: '/tmp/generated')

    plan = applier.plan(manifest)

    assert_equal 'prometheus_stack', plan.provider
    assert_equal 'dry_run', plan.mode
    assert_equal 'write', plan.operations.fetch(0).action
    assert_equal 'manifest_file', plan.operations.fetch(0).target
    assert_equal '/tmp/generated/checkout-api/prometheus_stack/manifest.json', plan.operations.fetch(0).payload.fetch(:path)
  end

  def test_manifest_bundle_diff_reports_update_when_existing_manifest_differs
    manifest = valid_prometheus_manifest
    manifest[:artifacts][:recording_rules] = [
      { record: 'slo:checkout-api:availability', expr: 'new_expr', labels: { service: 'checkout-api' } }
    ]

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'checkout-api', 'prometheus_stack', 'manifest.json')
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(
        valid_prometheus_manifest.merge(
          artifacts: valid_prometheus_manifest[:artifacts].merge(
            recording_rules: [
              { record: 'slo:checkout-api:availability', expr: 'old_expr', labels: { service: 'checkout-api' } }
            ]
          )
        )
      ))

      applier = SloRulesEngine::Appliers::ManifestBundle.new(output_dir: dir)
      plan = applier.diff(manifest)

      assert_equal 'diff', plan.mode
      assert_equal 'update', plan.operations.fetch(0).action
      assert_equal ['artifacts.recording_rules[0].expr'], plan.operations.fetch(0).changes
      assert_equal path, plan.operations.fetch(0).payload.fetch(:path)
    end
  end

  def test_external_generator_plan_records_sloth_handoff
    manifest = valid_sloth_manifest
    applier = SloRulesEngine::Appliers::ManifestBundle.new(output_dir: '/tmp/generated')

    plan = applier.plan(manifest)

    assert_equal %w[write handoff], plan.operations.map(&:action)
    assert_equal 'external_generator', plan.operations.fetch(1).target
    assert_includes plan.operations.fetch(1).payload.fetch(:command), 'sloth generate'
    assert_equal '/tmp/generated/checkout-api/sloth/manifest.json', plan.operations.fetch(1).payload.fetch(:input_manifest)
  end

  private

  def valid_prometheus_manifest
    {
      provider: 'prometheus_stack',
      service: 'checkout-api',
      artifacts: {
        recording_rules: [],
        burn_rate_rules: [],
        missing_telemetry_rules: [],
        alert_rules: [],
        alertmanager_routes: [],
        grafana_dashboards: []
      }
    }
  end

  def valid_sloth_manifest
    {
      provider: 'sloth',
      service: 'checkout-api',
      artifacts: {
        sloth_specs: []
      }
    }
  end
end
