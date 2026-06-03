# frozen_string_literal: true

require_relative 'support/datadog_apply_test_case'

class DatadogApplyTest < Minitest::Test
  def test_datadog_apply_translates_payloads_and_resolves_slo_ids_for_monitors
    client = FakeDatadogClient.new
    applier = SloRulesEngine::Appliers::Datadog.new(client: client)

    plan = applier.apply(@manifest)

    assert_equal 'live', plan.mode
    assert_equal [
      ['POST', '/api/v1/slo'],
      ['POST', '/api/v1/monitor'],
      ['POST', '/api/v1/monitor'],
      ['POST', '/api/v1/dashboard']
    ], client.requests.map { |request| [request.fetch(:method), request.fetch(:path)] }
    assert_equal 1, client.created_and_waited_slos.length

    slo_payload = client.requests.fetch(0).fetch(:payload)
    assert_equal 'metric', slo_payload.fetch(:type)
    assert_equal 'checkout-api http-requests public-api successful-requests', slo_payload.fetch(:name)
    assert_equal '30d', slo_payload.fetch(:timeframe)
    assert_equal 99.9, slo_payload.fetch(:target_threshold)
    assert_equal 'count:http.server.request.duration{route:/checkout,service:checkout-api,status:success}.as_count()',
                 slo_payload.fetch(:query).fetch(:numerator)
    assert_equal 'count:http.server.request.duration{route:/checkout,service:checkout-api}.as_count()',
                 slo_payload.fetch(:query).fetch(:denominator)
    assert_includes slo_payload.fetch(:tags), 'source_ref:artifacts.slos.0'

    burn_rate_payload = client.requests.fetch(1).fetch(:payload)
    assert_equal 'slo alert', burn_rate_payload.fetch(:type)
    assert_includes burn_rate_payload.fetch(:query), 'burn_rate("generated-slo-1").over("30d").long_window("1h").short_window("5m") > 14.4'
    assert_equal 14.4, burn_rate_payload.fetch(:options).fetch(:thresholds).fetch(:critical)
    assert_includes burn_rate_payload.fetch(:tags), 'source_ref:artifacts.monitors.0'

    telemetry_gap_payload = client.requests.fetch(2).fetch(:payload)
    assert_equal 'query alert', telemetry_gap_payload.fetch(:type)
    assert_equal true, telemetry_gap_payload.fetch(:options).fetch(:notify_no_data)
    assert_includes telemetry_gap_payload.fetch(:query), 'avg(last_10m):count:http.server.request.duration{route:/checkout,service:checkout-api}.as_count() < 0'
    assert_includes telemetry_gap_payload.fetch(:tags), 'source_ref:artifacts.telemetry_gap_monitors.0'

    dashboard_payload = client.requests.fetch(3).fetch(:payload)
    assert_equal 'ordered', dashboard_payload.fetch(:layout_type)
    assert_equal 'checkout-api SLO decision dashboard', dashboard_payload.fetch(:title)
    assert_includes dashboard_payload.fetch(:tags), 'managed_by:slo-rules-engine'
    assert_includes dashboard_payload.fetch(:tags), 'service:checkout-api'
    assert_includes dashboard_payload.fetch(:tags), 'source_ref:artifacts.dashboards.0'
    assert_equal %w[service sli sli_instance slo],
                 dashboard_payload.fetch(:template_variables).map { |variable| variable.fetch(:name) }
    assert_equal 'p95:http.server.request.duration{route:/checkout,service:checkout-api}',
                 dashboard_payload.fetch(:widgets).fetch(1).fetch(:definition).fetch(:requests).fetch(0).fetch(:q)
  end


  def test_datadog_apply_translates_time_slice_slo_payloads_for_counter_ratio_slos
    manifest = time_slice_manifest
    client = FakeDatadogClient.new
    applier = SloRulesEngine::Appliers::Datadog.new(client: client)

    plan = applier.apply(manifest)

    assert_equal 'live', plan.mode
    slo_payload = client.requests.fetch(0).fetch(:payload)
    assert_equal 'time_slice', slo_payload.fetch(:type)
    assert_equal 99.9, slo_payload.fetch(:target_threshold)
    assert_equal '30d', slo_payload.fetch(:timeframe)
    assert_includes slo_payload.fetch(:tags), 'source_ref:artifacts.slos.0'

    specification = slo_payload.fetch(:sli_specification).fetch(:time_slice)
    assert_equal '>=', specification.fetch(:comparator)
    assert_equal 300, specification.fetch(:query_interval_seconds)
    assert_equal 0.999, specification.fetch(:threshold)
    assert_equal [{ formula: 'success / total' }], specification.fetch(:query).fetch(:formulas)
    assert_equal [
      {
        data_source: 'metrics',
        name: 'total',
        query: 'sum:http.server.request.duration{route:/checkout,service:checkout-api}.as_count()'
      },
      {
        data_source: 'metrics',
        name: 'success',
        query: 'sum:http.server.request.duration{route:/checkout,service:checkout-api,status:success}.as_count()'
      }
    ], specification.fetch(:query).fetch(:queries)
  end


  def test_datadog_apply_translates_time_slice_slo_payloads_for_threshold_based_distribution_slos
    manifest = threshold_time_slice_manifest
    client = FakeDatadogClient.new
    applier = SloRulesEngine::Appliers::Datadog.new(client: client)

    plan = applier.apply(manifest)

    assert_equal 'live', plan.mode
    slo_payload = client.requests.fetch(0).fetch(:payload)
    assert_equal 'time_slice', slo_payload.fetch(:type)
    assert_equal 99.9, slo_payload.fetch(:target_threshold)

    specification = slo_payload.fetch(:sli_specification).fetch(:time_slice)
    assert_equal '<=', specification.fetch(:comparator)
    assert_equal 300, specification.fetch(:query_interval_seconds)
    assert_equal 0.3, specification.fetch(:threshold)
    assert_equal [{ formula: 'main' }], specification.fetch(:query).fetch(:formulas)
    assert_equal [
      {
        data_source: 'metrics',
        name: 'main',
        query: 'p95:http.server.request.duration{route:/checkout,service:checkout-api}'
      }
    ], specification.fetch(:query).fetch(:queries)
  end


  def test_datadog_apply_infers_threshold_based_distribution_time_slice_query_when_provider_query_is_absent
    manifest = inferred_distribution_time_slice_manifest
    client = FakeDatadogClient.new
    applier = SloRulesEngine::Appliers::Datadog.new(client: client)

    plan = applier.apply(manifest)

    assert_equal 'live', plan.mode
    slo_payload = client.requests.fetch(0).fetch(:payload)
    specification = slo_payload.fetch(:sli_specification).fetch(:time_slice)
    assert_equal [
      {
        data_source: 'metrics',
        name: 'main',
        query: 'p99.9:http.server.request.duration{route:/checkout,service:checkout-api}'
      }
    ], specification.fetch(:query).fetch(:queries)

    dashboard_payload = client.requests.fetch(3).fetch(:payload)
    assert_equal 'p99.9:http.server.request.duration{route:/checkout,service:checkout-api}',
                 dashboard_payload.fetch(:widgets).fetch(1).fetch(:definition).fetch(:requests).fetch(0).fetch(:q)
  end


  def test_datadog_apply_infers_threshold_based_gauge_time_slice_query_when_provider_query_is_absent
    manifest = inferred_gauge_time_slice_manifest
    client = FakeDatadogClient.new
    applier = SloRulesEngine::Appliers::Datadog.new(client: client)

    plan = applier.apply(manifest)

    assert_equal 'live', plan.mode
    slo_payload = client.requests.fetch(0).fetch(:payload)
    specification = slo_payload.fetch(:sli_specification).fetch(:time_slice)
    assert_equal '<=', specification.fetch(:comparator)
    assert_equal 5.0, specification.fetch(:threshold)
    assert_equal [
      {
        data_source: 'metrics',
        name: 'main',
        query: 'max:worker.queue.depth{queue:default,service:checkout-api}'
      }
    ], specification.fetch(:query).fetch(:queries)

    dashboard_payload = client.requests.fetch(3).fetch(:payload)
    assert_equal 'max:worker.queue.depth{queue:default,service:checkout-api}',
                 dashboard_payload.fetch(:widgets).fetch(1).fetch(:definition).fetch(:requests).fetch(0).fetch(:q)
  end


  def test_datadog_apply_infers_threshold_based_counter_time_slice_query_when_provider_query_is_absent
    manifest = inferred_counter_time_slice_manifest
    client = FakeDatadogClient.new
    applier = SloRulesEngine::Appliers::Datadog.new(client: client)

    plan = applier.apply(manifest)

    assert_equal 'live', plan.mode
    slo_payload = client.requests.fetch(0).fetch(:payload)
    specification = slo_payload.fetch(:sli_specification).fetch(:time_slice)
    assert_equal '>=', specification.fetch(:comparator)
    assert_equal 10.0, specification.fetch(:threshold)
    assert_equal [
      {
        data_source: 'metrics',
        name: 'main',
        query: 'sum:http.server.request.count{route:/checkout,service:checkout-api}.as_count()'
      }
    ], specification.fetch(:query).fetch(:queries)

    dashboard_payload = client.requests.fetch(3).fetch(:payload)
    assert_equal 'sum:http.server.request.count{route:/checkout,service:checkout-api}.as_count()',
                 dashboard_payload.fetch(:widgets).fetch(1).fetch(:definition).fetch(:requests).fetch(0).fetch(:q)
  end


  def test_datadog_applier_diff_reports_noop_when_time_slice_payloads_match
    manifest = time_slice_manifest
    slo_name = manifest.fetch(:artifacts).fetch(:slos).fetch(0).fetch(:name)
    client = FakeDatadogClient.new(
      slos: {
        slo_name => {
          id: 'slo-123',
          payload: {
            name: slo_name,
            type: 'time_slice',
            description: "Generated by slo-rules-engine for #{manifest.fetch(:service)} from artifacts.slos[0]",
            sli_specification: {
              time_slice: {
                comparator: '>=',
                query_interval_seconds: 300,
                threshold: 0.999,
                query: {
                  formulas: [{ formula: 'success / total' }],
                  queries: [
                    {
                      data_source: 'metrics',
                      name: 'total',
                      query: 'sum:http.server.request.duration{route:/checkout,service:checkout-api}.as_count()'
                    },
                    {
                      data_source: 'metrics',
                      name: 'success',
                      query: 'sum:http.server.request.duration{route:/checkout,service:checkout-api,status:success}.as_count()'
                    }
                  ]
                }
              }
            },
            tags: [
              'managed_by:slo-rules-engine',
              'service:checkout-api',
              'owner:payments-platform',
              'sli:http-requests',
              'sli_instance:public-api',
              'slo:successful-requests',
              'source_ref:artifacts.slos.0',
              'extra:backend-only-tag'
            ],
            thresholds: [{ timeframe: '30d', target: 99.9 }],
            timeframe: '30d',
            target_threshold: 99.9
          }
        }
      }
    )
    applier = SloRulesEngine::Appliers::Datadog.new(client: client)

    plan = applier.diff(manifest)

    assert_equal 'noop', plan.operations.fetch(0).action
    assert_equal [], plan.operations.fetch(0).changes
  end


  def test_datadog_applier_diff_reports_noop_when_inferred_distribution_time_slice_payloads_match
    manifest = inferred_distribution_time_slice_manifest
    slo_name = manifest.fetch(:artifacts).fetch(:slos).fetch(0).fetch(:name)
    client = FakeDatadogClient.new(
      slos: {
        slo_name => {
          id: 'slo-123',
          payload: {
            name: slo_name,
            type: 'time_slice',
            description: "Generated by slo-rules-engine for #{manifest.fetch(:service)} from artifacts.slos[0]",
            sli_specification: {
              time_slice: {
                comparator: '<=',
                query_interval_seconds: 300,
                threshold: 0.3,
                query: {
                  formulas: [{ formula: 'main' }],
                  queries: [
                    {
                      data_source: 'metrics',
                      name: 'main',
                      query: 'p99.9:http.server.request.duration{route:/checkout,service:checkout-api}'
                    }
                  ]
                }
              }
            },
            tags: [
              'managed_by:slo-rules-engine',
              'service:checkout-api',
              'owner:payments-platform',
              'sli:http-requests',
              'sli_instance:public-api',
              'slo:successful-requests',
              'source_ref:artifacts.slos.0',
              'extra:backend-only-tag'
            ],
            thresholds: [{ timeframe: '30d', target: 99.9 }],
            timeframe: '30d',
            target_threshold: 99.9
          }
        }
      }
    )
    applier = SloRulesEngine::Appliers::Datadog.new(client: client)

    plan = applier.diff(manifest)

    assert_equal 'noop', plan.operations.fetch(0).action
    assert_equal [], plan.operations.fetch(0).changes
  end


  def test_datadog_applier_diff_reports_noop_when_inferred_counter_time_slice_payloads_match
    manifest = inferred_counter_time_slice_manifest
    slo_name = manifest.fetch(:artifacts).fetch(:slos).fetch(0).fetch(:name)
    client = FakeDatadogClient.new(
      slos: {
        slo_name => {
          id: 'slo-123',
          payload: {
            name: slo_name,
            type: 'time_slice',
            description: "Generated by slo-rules-engine for #{manifest.fetch(:service)} from artifacts.slos[0]",
            sli_specification: {
              time_slice: {
                comparator: '>=',
                query_interval_seconds: 300,
                threshold: 10.0,
                query: {
                  formulas: [{ formula: 'main' }],
                  queries: [
                    {
                      data_source: 'metrics',
                      name: 'main',
                      query: 'sum:http.server.request.count{route:/checkout,service:checkout-api}.as_count()'
                    }
                  ]
                }
              }
            },
            tags: [
              'managed_by:slo-rules-engine',
              'service:checkout-api',
              'owner:payments-platform',
              'sli:http-requests',
              'sli_instance:public-api',
              'slo:successful-requests',
              'source_ref:artifacts.slos.0',
              'extra:backend-only-tag'
            ],
            thresholds: [{ timeframe: '30d', target: 99.9 }],
            timeframe: '30d',
            target_threshold: 99.9
          }
        }
      }
    )
    applier = SloRulesEngine::Appliers::Datadog.new(client: client)

    plan = applier.diff(manifest)

    assert_equal 'noop', plan.operations.fetch(0).action
    assert_equal [], plan.operations.fetch(0).changes
  end


  def test_datadog_applier_diff_reports_noop_when_threshold_based_time_slice_payloads_match
    manifest = threshold_time_slice_manifest
    slo_name = manifest.fetch(:artifacts).fetch(:slos).fetch(0).fetch(:name)
    client = FakeDatadogClient.new(
      slos: {
        slo_name => {
          id: 'slo-123',
          payload: {
            name: slo_name,
            type: 'time_slice',
            description: "Generated by slo-rules-engine for #{manifest.fetch(:service)} from artifacts.slos[0]",
            sli_specification: {
              time_slice: {
                comparator: '<=',
                query_interval_seconds: 300,
                threshold: 0.3,
                query: {
                  formulas: [{ formula: 'main' }],
                  queries: [
                    {
                      data_source: 'metrics',
                      name: 'main',
                      query: 'p95:http.server.request.duration{route:/checkout,service:checkout-api}'
                    }
                  ]
                }
              }
            },
            tags: [
              'managed_by:slo-rules-engine',
              'service:checkout-api',
              'owner:payments-platform',
              'sli:http-requests',
              'sli_instance:public-api',
              'slo:successful-requests',
              'source_ref:artifacts.slos.0',
              'extra:backend-only-tag'
            ],
            thresholds: [{ timeframe: '30d', target: 99.9 }],
            timeframe: '30d',
            target_threshold: 99.9
          }
        }
      }
    )
    applier = SloRulesEngine::Appliers::Datadog.new(client: client)

    plan = applier.diff(manifest)

    assert_equal 'noop', plan.operations.fetch(0).action
    assert_equal [], plan.operations.fetch(0).changes
  end


  def test_datadog_apply_skips_noop_operations_when_backend_payloads_match
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
    client = FakeDatadogClient.new(**state)
    applier = SloRulesEngine::Appliers::Datadog.new(client: client)

    plan = applier.apply(@manifest)

    assert_equal 'live', plan.mode
    assert_equal %w[noop noop noop noop], plan.operations.map(&:action)
    assert_equal [], client.requests
    assert_equal [], client.created_and_waited_slos
    assert_equal [], client.created_and_waited_monitors
  end


  def test_datadog_apply_recreates_stale_monitors_with_current_slo_ids
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

    plan = applier.apply(@manifest)

    assert_equal 'live', plan.mode
    assert_equal [
      ['PUT', '/api/v1/slo/slo-123'],
      ['DELETE', '/api/v1/monitor/456'],
      ['POST', '/api/v1/monitor']
    ], client.requests.first(3).map { |request| [request.fetch(:method), request.fetch(:path)] }
    assert_includes client.requests.fetch(2).fetch(:payload).fetch(:query), 'burn_rate("slo-123")'
  end


  def test_datadog_apply_rejects_live_update_when_ownership_match_is_weak
    slo_name = @manifest.fetch(:artifacts).fetch(:slos).fetch(0).fetch(:name)
    client = FakeDatadogClient.new(
      slos: {
        slo_name => {
          id: 'slo-123',
          match_identity: { strategy: 'name', confidence: 'medium' }
        }
      }
    )
    applier = SloRulesEngine::Appliers::Datadog.new(client: client)

    error = assert_raises(SloRulesEngine::Datadog::OwnershipError) do
      applier.apply(@manifest)
    end

    assert_equal [], client.requests
    assert_equal 'update', error.operation.action
    assert_equal({ strategy: 'name', confidence: 'medium' }, error.operation.match_identity)
    assert error.result.errors.any? do |entry|
      entry.path == 'match_identity' && entry.message.include?('managed source_ref identity')
    end
  end


  def test_datadog_apply_rejects_live_recreate_when_ownership_match_is_weak
    seed_applier = SloRulesEngine::Appliers::Datadog.new(client: FakeDatadogClient.new)
    desired_operations = seed_applier.plan(@manifest).operations
    slo_name = desired_operations.fetch(0).name
    monitor_name = desired_operations.fetch(1).name
    slo_payload = Marshal.load(Marshal.dump(desired_operations.fetch(0).payload))
    client = FakeDatadogClient.new(
      slos: {
        slo_name => {
          id: 'slo-123',
          payload: slo_payload,
          match_identity: { strategy: 'source_ref', confidence: 'high' }
        }
      },
      monitors: {
        monitor_name => {
          id: 456,
          payload: {
            query: 'burn_rate("stale-slo-999").over("30d").long_window("1h").short_window("5m") > 14.4'
          },
          match_identity: { strategy: 'name', confidence: 'medium' }
        }
      }
    )
    applier = SloRulesEngine::Appliers::Datadog.new(client: client)

    error = assert_raises(SloRulesEngine::Datadog::OwnershipError) do
      applier.apply(@manifest)
    end

    assert_equal [], client.requests
    assert_equal 'recreate', error.operation.action
    assert_equal({ strategy: 'name', confidence: 'medium' }, error.operation.match_identity)
  end


  def test_datadog_apply_rejects_unresolved_monitor_payload_references
    client = FakeDatadogClient.new(slo_create_response: { 'data' => [{}] })
    applier = SloRulesEngine::Appliers::Datadog.new(client: client)

    error = assert_raises(SloRulesEngine::Datadog::PayloadError) do
      applier.apply(@manifest)
    end

    assert_equal [['POST', '/api/v1/slo']], client.requests.map { |request| [request.fetch(:method), request.fetch(:path)] }
    assert error.result.errors.any? do |entry|
      entry.path == 'query' && entry.message.include?('unresolved SLO reference')
    end
  end


  def test_datadog_payload_validator_requires_managed_identity_tags
    operations = SloRulesEngine::Appliers::Datadog.new(client: FakeDatadogClient.new).plan(@manifest).operations

    slo_payload = Marshal.load(Marshal.dump(operations.fetch(0).payload))
    slo_payload[:tags].reject! { |tag| tag.start_with?('source_ref:') }
    slo_error = assert_raises(SloRulesEngine::Datadog::PayloadError) do
      SloRulesEngine::Datadog::PayloadValidator.validate!('datadog.slo', slo_payload)
    end
    assert slo_error.result.errors.any? { |entry| entry.path == 'tags.source_ref' && entry.message == 'is required' }

    monitor_payload = Marshal.load(Marshal.dump(operations.fetch(1).payload))
    monitor_payload[:tags].reject! { |tag| tag.start_with?('route_key:') }
    monitor_error = assert_raises(SloRulesEngine::Datadog::PayloadError) do
      SloRulesEngine::Datadog::PayloadValidator.validate!('datadog.monitor', monitor_payload)
    end
    assert monitor_error.result.errors.any? { |entry| entry.path == 'tags.route_key' && entry.message == 'is required' }

    dashboard_payload = Marshal.load(Marshal.dump(operations.fetch(3).payload))
    dashboard_payload[:tags].map! do |tag|
      tag.start_with?('source_ref:') ? 'source_ref:artifacts.monitors.0' : tag
    end
    dashboard_error = assert_raises(SloRulesEngine::Datadog::PayloadError) do
      SloRulesEngine::Datadog::PayloadValidator.validate!('datadog.dashboard', dashboard_payload)
    end
    assert dashboard_error.result.errors.any? do |entry|
      entry.path == 'tags.source_ref' && entry.message.include?('artifacts.dashboards.')
    end
  end


  def test_datadog_payload_validator_rejects_invalid_dashboard_contract
    dashboard_payload = Marshal.load(
      Marshal.dump(SloRulesEngine::Appliers::Datadog.new(client: FakeDatadogClient.new).plan(@manifest).operations.fetch(3).payload)
    )
    dashboard_payload[:template_variables] = [{ name: 'service', prefix: 'service', default: 'checkout-api' }]
    dashboard_payload[:widgets] = [
      {
        definition: {
          type: 'note',
          content: '',
          background_color: 'yellow'
        }
      },
      {
        definition: {
          type: 'timeseries',
          title: '',
          requests: [{ q: '' }]
        }
      }
    ]

    error = assert_raises(SloRulesEngine::Datadog::PayloadError) do
      SloRulesEngine::Datadog::PayloadValidator.validate!('datadog.dashboard', dashboard_payload)
    end

    assert error.result.errors.any? do |entry|
      entry.path == 'template_variables' && entry.message.include?('service, sli, sli_instance, slo')
    end
    assert error.result.errors.any? do |entry|
      entry.path == 'widgets[0].definition.background_color' && entry.message.include?('white')
    end
    assert error.result.errors.any? do |entry|
      entry.path == 'widgets[0].definition.content' && entry.message == 'is required'
    end
    assert error.result.errors.any? do |entry|
      entry.path == 'widgets[1].definition.title' && entry.message == 'is required'
    end
    assert error.result.errors.any? do |entry|
      entry.path == 'widgets[1].definition.requests[0].q' && entry.message == 'is required'
    end
  end


  def test_datadog_payload_validator_rejects_inconsistent_slo_threshold_contract
    slo_payload = Marshal.load(
      Marshal.dump(SloRulesEngine::Appliers::Datadog.new(client: FakeDatadogClient.new).plan(@manifest).operations.fetch(0).payload)
    )
    slo_payload[:target_threshold] = 95.0
    slo_payload[:thresholds][0][:timeframe] = '7d'

    error = assert_raises(SloRulesEngine::Datadog::PayloadError) do
      SloRulesEngine::Datadog::PayloadValidator.validate!('datadog.slo', slo_payload)
    end

    assert error.result.errors.any? do |entry|
      entry.path == 'thresholds[0].timeframe' && entry.message.include?('30d')
    end
    assert error.result.errors.any? do |entry|
      entry.path == 'target_threshold' && entry.message.include?('thresholds[0].target')
    end
  end


  def test_datadog_payload_validator_rejects_invalid_burn_rate_monitor_contract
    monitor_payload = Marshal.load(
      Marshal.dump(SloRulesEngine::Appliers::Datadog.new(client: FakeDatadogClient.new).plan(@manifest).operations.fetch(1).payload)
    )
    monitor_payload[:query] = 'burn_rate("slo-123").over("30d").long_window("1h").short_window("5m") > 9.9'
    monitor_payload[:options][:include_tags] = false
    monitor_payload[:options][:thresholds][:critical] = 14.4

    error = assert_raises(SloRulesEngine::Datadog::PayloadError) do
      SloRulesEngine::Datadog::PayloadValidator.validate!('datadog.monitor', monitor_payload)
    end

    assert error.result.errors.any? do |entry|
      entry.path == 'options.include_tags' && entry.message.include?('true')
    end
    assert error.result.errors.any? do |entry|
      entry.path == 'options.thresholds.critical' && entry.message.include?('query threshold')
    end
  end


  def test_datadog_payload_validator_rejects_invalid_telemetry_gap_monitor_contract
    monitor_payload = Marshal.load(
      Marshal.dump(SloRulesEngine::Appliers::Datadog.new(client: FakeDatadogClient.new).plan(@manifest).operations.fetch(2).payload)
    )
    monitor_payload[:query] = 'avg(last_5m):count:http.server.request.duration{route:/checkout,service:checkout-api}.as_count() < 1'
    monitor_payload[:options][:notify_no_data] = false
    monitor_payload[:options][:no_data_timeframe] = 5
    monitor_payload[:options][:thresholds][:critical] = 1

    error = assert_raises(SloRulesEngine::Datadog::PayloadError) do
      SloRulesEngine::Datadog::PayloadValidator.validate!('datadog.monitor', monitor_payload)
    end

    assert error.result.errors.any? do |entry|
      entry.path == 'query' && entry.message.include?('avg(last_10m)')
    end
    assert error.result.errors.any? do |entry|
      entry.path == 'options.notify_no_data' && entry.message.include?('true')
    end
    assert error.result.errors.any? do |entry|
      entry.path == 'options.no_data_timeframe' && entry.message.include?('10')
    end
    assert error.result.errors.any? do |entry|
      entry.path == 'options.thresholds.critical' && entry.message.include?('0')
    end
  end

end
