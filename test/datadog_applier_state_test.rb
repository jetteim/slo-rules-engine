# frozen_string_literal: true

require_relative 'support/datadog_apply_test_case'

class DatadogApplyTest < Minitest::Test
  def test_datadog_applier_plans_slos_monitors_gap_monitors_and_dashboards
    applier = SloRulesEngine::Appliers::Datadog.new(client: FakeDatadogClient.new)

    plan = applier.plan(@manifest)

    assert_equal 'datadog', plan.provider
    assert_equal 'dry_run', plan.mode
    assert_equal %w[create_and_wait create create create], plan.operations.map(&:action)
    assert_equal ['datadog.slo', 'datadog.monitor', 'datadog.monitor', 'datadog.dashboard'], plan.operations.map(&:target)
    assert_equal ['artifacts.slos[0]', 'artifacts.monitors[0]', 'artifacts.telemetry_gap_monitors[0]', 'artifacts.dashboards[0]'], plan.operations.map(&:source)
    state_contract = plan.to_h.fetch(:state_contract)
    assert_equal 'ProviderStatePlan', state_contract.fetch(:kind)
    assert_equal 'checkout-api', state_contract.fetch(:service)
    assert_equal 'provider_manifest', state_contract.dig(:desired_state, :source)
    assert_equal 'backend_api', state_contract.dig(:observed_state, :source)
    assert_equal %w[create_and_wait create create create],
                 state_contract.fetch(:changes).map { |change| change.fetch(:action) }
    assert_equal plan.operations.fetch(0).payload,
                 state_contract.fetch(:changes).fetch(0).fetch(:desired)
  end


  def test_datadog_applier_uses_backend_state_to_plan_updates
    slo_name = @manifest.fetch(:artifacts).fetch(:slos).fetch(0).fetch(:name)
    monitor_name = @manifest.fetch(:artifacts).fetch(:monitors).fetch(0).fetch(:name)
    gap_monitor_name = @manifest.fetch(:artifacts).fetch(:telemetry_gap_monitors).fetch(0).fetch(:name)
    client = FakeDatadogClient.new(
      slos: { slo_name => { id: 'slo-123' } },
      monitors: { monitor_name => { id: 456 } }
    )
    applier = SloRulesEngine::Appliers::Datadog.new(client: client)

    plan = applier.plan(@manifest)

    assert_equal 'update', plan.operations.fetch(0).action
    assert_equal 'slo-123', plan.operations.fetch(0).backend_id
    assert_equal 'update', plan.operations.fetch(1).action
    assert_equal 456, plan.operations.fetch(1).backend_id
    assert_equal 'create', plan.operations.fetch(2).action
    assert_equal [{ name: slo_name, source: 'artifacts.slos[0]' }], client.existing_state_requests.fetch(0).fetch(:slos)
    assert_equal [
      { name: monitor_name, source: 'artifacts.monitors[0]' },
      { name: gap_monitor_name, source: 'artifacts.telemetry_gap_monitors[0]' }
    ],
                 client.existing_state_requests.fetch(0).fetch(:monitors)
  end


  def test_datadog_applier_marks_stale_burn_rate_monitors_for_recreate
    slo_name = @manifest.fetch(:artifacts).fetch(:slos).fetch(0).fetch(:name)
    monitor_name = @manifest.fetch(:artifacts).fetch(:monitors).fetch(0).fetch(:name)
    client = FakeDatadogClient.new(
      slos: { slo_name => { id: 'slo-123' } },
      monitors: {
        monitor_name => {
          id: 456,
          payload: {
            query: 'burn_rate("stale-slo-999").over("30d").long_window("1h").short_window("5m") > 14.4'
          }
        }
      }
    )
    applier = SloRulesEngine::Appliers::Datadog.new(client: client)

    plan = applier.plan(@manifest)

    assert_equal 'update', plan.operations.fetch(0).action
    assert_equal 'recreate', plan.operations.fetch(1).action
    assert_equal 456, plan.operations.fetch(1).backend_id
    assert_equal 'high', plan.operations.fetch(1).risk.fetch(:level)
    assert_includes plan.operations.fetch(1).risk.fetch(:reasons), 'recreate_deletes_existing_monitor'
    assert_includes plan.operations.fetch(1).risk.fetch(:reasons), 'alert_coverage_may_drop'
    assert_equal 1, plan.to_h.fetch(:summary).fetch(:risky_operations)
    assert_equal 'high', plan.to_h.fetch(:summary).fetch(:highest_risk_level)
  end


  def test_datadog_applier_rejects_invalid_manifest_schema
    manifest = Marshal.load(Marshal.dump(@manifest))
    manifest.fetch(:artifacts).fetch(:slos).fetch(0).fetch(:query).delete(:success_selector)
    applier = SloRulesEngine::Appliers::Datadog.new(client: FakeDatadogClient.new)

    error = assert_raises(SloRulesEngine::ManifestSchemaError) do
      applier.plan(manifest)
    end

    assert error.result.errors.any? do |entry|
      entry.path == 'artifacts.slos[0].query.success_selector' && entry.message == 'is required'
    end
  end


  def test_datadog_applier_diff_reports_noop_when_payloads_match
    seed_applier = SloRulesEngine::Appliers::Datadog.new(client: FakeDatadogClient.new)
    desired_operations = seed_applier.plan(@manifest).operations
    burn_rate_payload = Marshal.load(Marshal.dump(desired_operations.fetch(1).payload))
    burn_rate_payload[:query] = burn_rate_payload.fetch(:query).gsub(
      '__SLO_REF__[checkout-api http-requests public-api successful-requests]',
      'slo-123'
    )
    state = {
      slos: {
        desired_operations.fetch(0).name => {
          id: 'slo-123',
          payload: desired_operations.fetch(0).payload
        }
      },
      monitors: {
        desired_operations.fetch(1).name => {
          id: 456,
          payload: burn_rate_payload
        },
        desired_operations.fetch(2).name => {
          id: 789,
          payload: desired_operations.fetch(2).payload
        }
      },
      dashboards: {
        desired_operations.fetch(3).name => {
          id: 'dashboard-123',
          payload: desired_operations.fetch(3).payload
        }
      }
    }
    applier = SloRulesEngine::Appliers::Datadog.new(client: FakeDatadogClient.new(**state))

    plan = applier.diff(@manifest)

    assert_equal 'diff', plan.mode
    assert_equal %w[noop noop noop noop], plan.operations.map(&:action)
    assert_equal [], plan.operations.fetch(0).changes
  end


  def test_datadog_applier_import_returns_existing_backend_state
    slo_name = @manifest.fetch(:artifacts).fetch(:slos).fetch(0).fetch(:name)
    monitor_name = @manifest.fetch(:artifacts).fetch(:monitors).fetch(0).fetch(:name)
    dashboard_name = @manifest.fetch(:artifacts).fetch(:dashboards).fetch(0).fetch(:title)
    client = FakeDatadogClient.new(
      slos: { slo_name => { id: 'slo-123', payload: { type: 'metric' } } },
      monitors: { monitor_name => { id: 456, payload: { type: 'slo alert' } } },
      dashboards: { dashboard_name => { id: 'dashboard-123', payload: { layout_type: 'ordered' } } }
    )
    applier = SloRulesEngine::Appliers::Datadog.new(client: client)

    imported = applier.import(@manifest)

    assert_equal 'datadog', imported.provider
    assert_equal 'checkout-api', imported.service
    assert_equal 'backend_api', imported.source
    assert_equal 'slo-123', imported.state.fetch(:slos).fetch(slo_name).fetch(:id)
    assert_equal [{ name: slo_name, source: 'artifacts.slos[0]' }], client.existing_state_requests.fetch(0).fetch(:slos)
    assert_equal [
      { name: monitor_name, source: 'artifacts.monitors[0]' },
      { name: @manifest.fetch(:artifacts).fetch(:telemetry_gap_monitors).fetch(0).fetch(:name), source: 'artifacts.telemetry_gap_monitors[0]' }
    ],
                 client.existing_state_requests.fetch(0).fetch(:monitors)
    state_contract = imported.to_h.fetch(:state_contract)
    assert_equal 'ProviderStateImport', state_contract.fetch(:kind)
    assert_equal 'provider_manifest', state_contract.dig(:desired_state, :source)
    assert_equal 'backend_api', state_contract.dig(:observed_state, :source)
    assert_equal 'slo-123',
                 state_contract.dig(:observed_state, :resources, :slos, slo_name, :id)
  end


  def test_datadog_applier_import_reports_missing_expected_backend_resources
    applier = SloRulesEngine::Appliers::Datadog.new(client: FakeDatadogClient.new)

    imported = applier.import(@manifest)

    assert_equal 'datadog', imported.provider
    assert_equal 'checkout-api', imported.service
    assert_equal 'backend_api', imported.source
    assert_equal 4, imported.findings.length
    assert_equal ['missing_backend_resource'], imported.findings.map { |finding| finding[:code] }.uniq
    assert_equal ['artifacts.dashboards[0]', 'artifacts.monitors[0]', 'artifacts.slos[0]', 'artifacts.telemetry_gap_monitors[0]'],
                 imported.findings.map { |finding| finding[:source] }.sort
  end


  def test_datadog_applier_import_reports_orphan_managed_backend_resources
    slo_name = @manifest.fetch(:artifacts).fetch(:slos).fetch(0).fetch(:name)
    monitor_name = @manifest.fetch(:artifacts).fetch(:monitors).fetch(0).fetch(:name)
    gap_monitor_name = @manifest.fetch(:artifacts).fetch(:telemetry_gap_monitors).fetch(0).fetch(:name)
    dashboard_name = @manifest.fetch(:artifacts).fetch(:dashboards).fetch(0).fetch(:title)
    client = FakeDatadogClient.new(
      slos: { slo_name => { id: 'slo-123', payload: { type: 'metric' } } },
      monitors: {
        monitor_name => { id: 456, payload: { type: 'slo alert' } },
        gap_monitor_name => { id: 789, payload: { type: 'query alert' } }
      },
      dashboards: { dashboard_name => { id: 'dashboard-123', payload: { layout_type: 'ordered' } } },
      managed_state: {
        slos: [
          { id: 'slo-123', name: slo_name },
          { id: 'slo-orphan', name: 'checkout-api orphan slo' }
        ],
        monitors: [
          { id: 456, name: monitor_name },
          { id: 789, name: gap_monitor_name },
          { id: 999, name: 'SLO burn rate: checkout-api/orphan-sli/orphan-instance/orphan-slo' }
        ],
        dashboards: [
          { id: 'dashboard-123', title: dashboard_name },
          { id: 'dashboard-orphan', title: 'checkout-api orphan dashboard' }
        ]
      }
    )
    applier = SloRulesEngine::Appliers::Datadog.new(client: client)

    imported = applier.import(@manifest)

    orphan_findings = imported.findings.select { |finding| finding[:code] == 'orphan_backend_resource' }

    assert_equal 3, orphan_findings.length
    assert_equal ['managed_state.dashboards[1]', 'managed_state.monitors[2]', 'managed_state.slos[1]'],
                 orphan_findings.map { |finding| finding[:source] }.sort
  end


  def test_datadog_applier_prune_returns_empty_plan_when_no_orphans_exist
    slo_name = @manifest.fetch(:artifacts).fetch(:slos).fetch(0).fetch(:name)
    monitor_name = @manifest.fetch(:artifacts).fetch(:monitors).fetch(0).fetch(:name)
    gap_monitor_name = @manifest.fetch(:artifacts).fetch(:telemetry_gap_monitors).fetch(0).fetch(:name)
    dashboard_name = @manifest.fetch(:artifacts).fetch(:dashboards).fetch(0).fetch(:title)
    client = FakeDatadogClient.new(
      slos: { slo_name => { id: 'slo-123' } },
      monitors: { monitor_name => { id: 456 }, gap_monitor_name => { id: 789 } },
      dashboards: { dashboard_name => { id: 'dashboard-123' } }
    )
    applier = SloRulesEngine::Appliers::Datadog.new(client: client)

    plan = applier.prune(@manifest)

    assert_equal 'dry_run', plan.mode
    assert plan.empty?
    assert_equal [], plan.operations
  end


  def test_datadog_applier_prune_uses_source_identity_when_backend_names_drift
    client = FakeDatadogClient.new(
      managed_state: {
        slos: [
          { id: 'slo-123', name: 'legacy checkout slo', source: 'artifacts.slos[0]' }
        ],
        monitors: [
          { id: 456, name: 'legacy burn monitor', source: 'artifacts.monitors[0]' },
          { id: 789, name: 'legacy telemetry gap monitor', source: 'artifacts.telemetry_gap_monitors[0]' }
        ],
        dashboards: [
          { id: 'dashboard-123', title: 'legacy dashboard title', source: 'artifacts.dashboards[0]' }
        ]
      }
    )
    applier = SloRulesEngine::Appliers::Datadog.new(client: client)

    plan = applier.prune(@manifest)

    assert plan.empty?
    assert_equal [], plan.operations
  end


  def test_datadog_applier_prune_plans_delete_operations_for_orphan_managed_resources
    slo_name = @manifest.fetch(:artifacts).fetch(:slos).fetch(0).fetch(:name)
    monitor_name = @manifest.fetch(:artifacts).fetch(:monitors).fetch(0).fetch(:name)
    gap_monitor_name = @manifest.fetch(:artifacts).fetch(:telemetry_gap_monitors).fetch(0).fetch(:name)
    dashboard_name = @manifest.fetch(:artifacts).fetch(:dashboards).fetch(0).fetch(:title)
    client = FakeDatadogClient.new(
      slos: { slo_name => { id: 'slo-123' } },
      monitors: { monitor_name => { id: 456 }, gap_monitor_name => { id: 789 } },
      dashboards: { dashboard_name => { id: 'dashboard-123' } },
      managed_state: {
        slos: [
          { id: 'slo-123', name: slo_name },
          { id: 'slo-orphan', name: 'checkout-api orphan slo' }
        ],
        monitors: [
          { id: 456, name: monitor_name },
          { id: 789, name: gap_monitor_name },
          { id: 999, name: 'SLO burn rate: checkout-api/orphan-sli/orphan-instance/orphan-slo' }
        ],
        dashboards: [
          { id: 'dashboard-123', title: dashboard_name },
          { id: 'dashboard-orphan', title: 'checkout-api orphan dashboard' }
        ]
      }
    )
    applier = SloRulesEngine::Appliers::Datadog.new(client: client)

    plan = applier.prune(@manifest)

    assert_equal 'dry_run', plan.mode
    assert_equal [
      ['datadog.monitor', 999],
      ['datadog.dashboard', 'dashboard-orphan'],
      ['datadog.slo', 'slo-orphan']
    ], plan.operations.map { |operation| [operation.target, operation.backend_id] }
    assert_equal ['high', 'medium', 'high'], plan.operations.map { |operation| operation.risk.fetch(:level) }
    assert_equal 3, plan.to_h.fetch(:summary).fetch(:risky_operations)
    assert_equal 'high', plan.to_h.fetch(:summary).fetch(:highest_risk_level)
    assert_equal({ 'high' => 2, 'medium' => 1 }, plan.to_h.fetch(:summary).fetch(:operations_by_risk))
  end


  def test_datadog_applier_prune_deletes_orphan_managed_resources
    slo_name = @manifest.fetch(:artifacts).fetch(:slos).fetch(0).fetch(:name)
    monitor_name = @manifest.fetch(:artifacts).fetch(:monitors).fetch(0).fetch(:name)
    gap_monitor_name = @manifest.fetch(:artifacts).fetch(:telemetry_gap_monitors).fetch(0).fetch(:name)
    dashboard_name = @manifest.fetch(:artifacts).fetch(:dashboards).fetch(0).fetch(:title)
    client = FakeDatadogClient.new(
      managed_state: {
        slos: [
          { id: 'slo-123', name: slo_name, source: 'artifacts.slos[0]' },
          { id: 'slo-orphan', name: 'checkout-api orphan slo', source: 'orphan.slos[0]' }
        ],
        monitors: [
          { id: 456, name: monitor_name, source: 'artifacts.monitors[0]' },
          { id: 789, name: gap_monitor_name, source: 'artifacts.telemetry_gap_monitors[0]' },
          { id: 999, name: 'SLO burn rate: checkout-api/orphan-sli/orphan-instance/orphan-slo', source: 'orphan.monitors[0]' }
        ],
        dashboards: [
          { id: 'dashboard-123', title: dashboard_name, source: 'artifacts.dashboards[0]' },
          { id: 'dashboard-orphan', title: 'checkout-api orphan dashboard', source: 'orphan.dashboards[0]' }
        ]
      }
    )
    applier = SloRulesEngine::Appliers::Datadog.new(client: client)

    plan = applier.prune(@manifest, mode: 'live')

    assert_equal 'live', plan.mode
    assert_equal [
      ['DELETE', '/api/v1/monitor/999'],
      ['DELETE', '/api/v1/dashboard/dashboard-orphan'],
      ['DELETE', '/api/v1/slo/slo-orphan?force=true']
    ], client.requests.map { |request| [request.fetch(:method), request.fetch(:path)] }
  end


  def test_datadog_prune_rejects_live_delete_when_ownership_match_is_weak
    slo_name = @manifest.fetch(:artifacts).fetch(:slos).fetch(0).fetch(:name)
    monitor_name = @manifest.fetch(:artifacts).fetch(:monitors).fetch(0).fetch(:name)
    gap_monitor_name = @manifest.fetch(:artifacts).fetch(:telemetry_gap_monitors).fetch(0).fetch(:name)
    dashboard_name = @manifest.fetch(:artifacts).fetch(:dashboards).fetch(0).fetch(:title)
    client = FakeDatadogClient.new(
      managed_state: {
        slos: [
          { id: 'slo-123', name: slo_name },
          { id: 'slo-orphan', name: 'checkout-api orphan slo' }
        ],
        monitors: [
          { id: 456, name: monitor_name },
          { id: 789, name: gap_monitor_name },
          { id: 999, name: 'SLO burn rate: checkout-api/orphan-sli/orphan-instance/orphan-slo' }
        ],
        dashboards: [
          { id: 'dashboard-123', title: dashboard_name },
          { id: 'dashboard-orphan', title: 'checkout-api orphan dashboard' }
        ]
      }
    )
    applier = SloRulesEngine::Appliers::Datadog.new(client: client)

    error = assert_raises(SloRulesEngine::Datadog::OwnershipError) do
      applier.prune(@manifest, mode: 'live')
    end

    assert_equal [], client.requests
    assert_equal 'delete', error.operation.action
    assert_equal({ strategy: 'service_scope_only', confidence: 'low' }, error.operation.match_identity)
  end

end
