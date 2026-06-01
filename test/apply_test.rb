# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/slo_rules_engine'
require 'tmpdir'
require 'yaml'

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

  def test_apply_plan_serializes_change_impact_summary
    operations = [
      SloRulesEngine::ApplyOperation.new(action: 'create', target: 'datadog.slo', name: 'slo', source: 'artifacts.slos[0]'),
      SloRulesEngine::ApplyOperation.new(action: 'noop', target: 'datadog.monitor', name: 'burn', source: 'artifacts.monitors[0]'),
      SloRulesEngine::ApplyOperation.new(
        action: 'delete',
        target: 'datadog.dashboard',
        name: 'dashboard',
        source: 'artifacts.dashboards[0]',
        risk: {
          level: 'medium',
          reasons: ['prune_deletes_dashboard']
        }
      )
    ]
    plan = SloRulesEngine::ApplyPlan.new(provider: 'datadog', mode: 'diff', operations: operations)

    payload = plan.to_h

    assert_equal 3, payload.fetch(:summary).fetch(:total_operations)
    assert_equal 2, payload.fetch(:summary).fetch(:actionable_operations)
    assert_equal 1, payload.fetch(:summary).fetch(:destructive_operations)
    assert_equal 1, payload.fetch(:summary).fetch(:risky_operations)
    assert_equal 'medium', payload.fetch(:summary).fetch(:highest_risk_level)
    assert_equal({ 'create' => 1, 'noop' => 1, 'delete' => 1 }, payload.fetch(:summary).fetch(:operations_by_action))
    assert_equal({ 'datadog.slo' => 1, 'datadog.monitor' => 1, 'datadog.dashboard' => 1 }, payload.fetch(:summary).fetch(:operations_by_target))
    assert_equal({ 'medium' => 1 }, payload.fetch(:summary).fetch(:operations_by_risk))
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

  def test_manifest_bundle_plan_reports_noop_when_existing_manifest_matches
    manifest = valid_prometheus_manifest

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'checkout-api', 'prometheus_stack', 'manifest.json')
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(manifest))

      applier = SloRulesEngine::Appliers::ManifestBundle.new(output_dir: dir)
      plan = applier.plan(manifest)

      assert_equal 'dry_run', plan.mode
      assert_equal 'noop', plan.operations.fetch(0).action
      assert_equal path, plan.operations.fetch(0).payload.fetch(:path)
    end
  end

  def test_manifest_bundle_apply_skips_manifest_write_when_existing_manifest_matches
    manifest = valid_prometheus_manifest

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'checkout-api', 'prometheus_stack', 'manifest.json')
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(manifest))

      applier = SloRulesEngine::Appliers::ManifestBundle.new(output_dir: dir)
      plan = applier.apply(manifest)

      assert_equal 'live', plan.mode
      assert_equal 'noop', plan.operations.fetch(0).action
      assert_equal manifest, JSON.parse(File.read(path), symbolize_names: true)
    end
  end

  def test_external_generator_plan_records_sloth_handoff
    manifest = valid_sloth_manifest
    applier = SloRulesEngine::Appliers::ManifestBundle.new(output_dir: '/tmp/generated')

    plan = applier.plan(manifest)

    assert_equal %w[write write handoff], plan.operations.map(&:action)
    assert_equal 'external_generator_input', plan.operations.fetch(1).target
    assert_equal '/tmp/generated/checkout-api/sloth/generated/sloth.yaml', plan.operations.fetch(1).payload.fetch(:path)
    assert_equal manifest.fetch(:artifacts).fetch(:sloth_specs).fetch(0), plan.operations.fetch(1).payload.fetch(:spec)
    assert_equal 'external_generator', plan.operations.fetch(2).target
    assert_includes plan.operations.fetch(2).payload.fetch(:command), 'sloth generate'
    assert_includes plan.operations.fetch(2).payload.fetch(:command), '-i /tmp/generated/checkout-api/sloth/generated/sloth.yaml'
    assert_equal '/tmp/generated/checkout-api/sloth/manifest.json', plan.operations.fetch(2).payload.fetch(:input_manifest)
    assert_equal '/tmp/generated/checkout-api/sloth/generated/sloth.yaml', plan.operations.fetch(2).payload.fetch(:input_spec)
    assert_equal ['/tmp/generated/checkout-api/sloth/generated/sloth.yaml'], plan.operations.fetch(2).payload.fetch(:input_specs)
    assert_equal '/tmp/generated/manifest-review/sloth.json', plan.operations.fetch(2).payload.fetch(:manifest_review_report)
    assert_equal 'rules-ctl manifest-review --provider=sloth --manifest=/tmp/generated/checkout-api/sloth/manifest.json --report=/tmp/generated/manifest-review/sloth.json',
                 plan.operations.fetch(2).payload.fetch(:manifest_review_command)
    assert_equal(
      {
        required: true,
        report: '/tmp/generated/manifest-review/sloth.json',
        finding_codes: %w[stale_manifest_review_report stale_handoff_review_report]
      },
      plan.operations.fetch(2).payload.fetch(:manifest_review_freshness)
    )
  end

  def test_external_generator_plan_keeps_handoff_when_manifest_file_is_noop
    manifest = valid_sloth_manifest

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'checkout-api', 'sloth', 'manifest.json')
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(manifest))

      applier = SloRulesEngine::Appliers::ManifestBundle.new(output_dir: dir)
      plan = applier.plan(manifest)

      assert_equal %w[noop write handoff], plan.operations.map(&:action)
      assert_equal path, plan.operations.fetch(2).payload.fetch(:input_manifest)
      assert_equal File.join(dir, 'checkout-api', 'sloth', 'generated', 'sloth.yaml'), plan.operations.fetch(2).payload.fetch(:input_spec)
    end
  end

  def test_manifest_bundle_apply_writes_sloth_external_generator_input
    manifest = valid_sloth_manifest

    Dir.mktmpdir do |dir|
      applier = SloRulesEngine::Appliers::ManifestBundle.new(output_dir: dir)
      plan = applier.apply(manifest)

      spec_path = File.join(dir, 'checkout-api', 'sloth', 'generated', 'sloth.yaml')
      assert_equal %w[write write handoff], plan.operations.map(&:action)
      assert File.exist?(spec_path), "expected #{spec_path} to exist"

      spec = YAML.safe_load(File.read(spec_path), permitted_classes: [], aliases: false)
      assert_equal 'prometheus/v1', spec.fetch('version')
      assert_equal 'checkout-api', spec.fetch('service')
      assert_equal 'checkout-slo', spec.fetch('slos').fetch(0).fetch('name')
    end
  end

  def test_manifest_bundle_diff_reports_sloth_external_generator_input_drift
    manifest = valid_sloth_manifest

    Dir.mktmpdir do |dir|
      manifest_path = File.join(dir, 'checkout-api', 'sloth', 'manifest.json')
      spec_path = File.join(dir, 'checkout-api', 'sloth', 'generated', 'sloth.yaml')
      FileUtils.mkdir_p(File.dirname(spec_path))
      File.write(manifest_path, JSON.pretty_generate(manifest))
      stale_spec = manifest.fetch(:artifacts).fetch(:sloth_specs).fetch(0).merge(labels: { owner: 'old-owner' })
      File.write(spec_path, YAML.dump(JSON.parse(JSON.generate(stale_spec))))

      applier = SloRulesEngine::Appliers::ManifestBundle.new(output_dir: dir)
      plan = applier.diff(manifest)

      spec_operation = plan.operations.find { |operation| operation.target == 'external_generator_input' }
      assert_equal 'update', spec_operation.action
      assert_equal spec_path, spec_operation.payload.fetch(:path)
      assert_includes spec_operation.changes, 'labels.owner'
    end
  end

  def test_manifest_bundle_prune_deletes_sloth_external_generator_input
    manifest = valid_sloth_manifest

    Dir.mktmpdir do |dir|
      manifest_path = File.join(dir, 'checkout-api', 'sloth', 'manifest.json')
      spec_path = File.join(dir, 'checkout-api', 'sloth', 'generated', 'sloth.yaml')
      FileUtils.mkdir_p(File.dirname(spec_path))
      File.write(manifest_path, JSON.pretty_generate(manifest))
      File.write(spec_path, YAML.dump(JSON.parse(JSON.generate(manifest.fetch(:artifacts).fetch(:sloth_specs).fetch(0)))))

      applier = SloRulesEngine::Appliers::ManifestBundle.new(output_dir: dir)
      plan = applier.prune(manifest, mode: 'live')

      assert_equal %w[delete delete], plan.operations.map(&:action)
      refute File.exist?(manifest_path), "expected #{manifest_path} to be deleted"
      refute File.exist?(spec_path), "expected #{spec_path} to be deleted"
    end
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
        sloth_specs: [
          {
            version: 'prometheus/v1',
            service: 'checkout-api',
            labels: { owner: 'payments-platform' },
            slos: [
              {
                name: 'checkout-slo',
                objective: 99.9,
                description: 'Checkout succeeds.',
                sli: {
                  events: {
                    error_query: 'sum(rate(http_requests_total{status!="success"}[5m]))',
                    total_query: 'sum(rate(http_requests_total[5m]))'
                  }
                },
                alerting: {
                  name: 'CheckoutSloBurn',
                  labels: { owner: 'payments-platform' },
                  page_alert: { labels: { severity: 'page' } },
                  ticket_alert: { labels: { severity: 'notification' } }
                }
              }
            ]
          }
        ]
      }
    }
  end
end
