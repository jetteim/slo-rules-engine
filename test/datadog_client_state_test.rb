# frozen_string_literal: true

require_relative 'support/datadog_apply_test_case'

class DatadogApplyTest < Minitest::Test
  def test_datadog_client_imports_existing_state_for_desired_resource_names
    http = RoutingHttp.new(
      '/api/v1/slo/search?page%5Bnumber%5D=0&page%5Bsize%5D=20&query=checkout-api+http-requests+public-api+successful-requests' => FakeResponse.new(
        '200',
        '{"data":{"attributes":{"slos":[{"data":{"id":"slo-123","attributes":{"name":"checkout-api http-requests public-api successful-requests","all_tags":["managed_by:slo-rules-engine"]}}}]}},"meta":{"pagination":{"total":1,"number":0,"last_number":0}}}'
      ),
      '/api/v1/slo/slo-123?with_configured_alert_ids=true' => FakeResponse.new(
        '200',
        '{"data":[{"id":"slo-123","name":"checkout-api http-requests public-api successful-requests","type":"metric","description":"Generated SLO from artifacts.slos[0]","query":{"numerator":"count:http.server.request.duration{route:/checkout,service:checkout-api,status:success}.as_count()","denominator":"count:http.server.request.duration{route:/checkout,service:checkout-api}.as_count()"},"tags":["managed_by:slo-rules-engine","service:checkout-api"],"thresholds":[{"timeframe":"30d","target":99.9}],"timeframe":"30d","target_threshold":99.9}]}'
      ),
      '/api/v1/monitor?monitor_tags=managed_by%3Aslo-rules-engine&name=SLO+burn+rate%3A+checkout-api%2Fhttp-requests%2Fpublic-api%2Fsuccessful-requests' => FakeResponse.new(
        '200',
        '[{"id":456,"name":"SLO burn rate: checkout-api/http-requests/public-api/successful-requests","tags":["managed_by:slo-rules-engine"]}]'
      ),
      '/api/v1/monitor/456' => FakeResponse.new(
        '200',
        '{"id":456,"name":"SLO burn rate: checkout-api/http-requests/public-api/successful-requests","type":"slo alert","query":"burn_rate(\"generated-slo-1\").over(\"30d\").long_window(\"1h\").short_window(\"5m\") > 14.4","message":"Error budget burn is elevated for checkout-api http-requests public-api successful-requests.","tags":["managed_by:slo-rules-engine","service:checkout-api","route_key:checkout-api"],"options":{"include_tags":true,"thresholds":{"critical":14.4}}}'
      ),
      '/api/v1/dashboard/lists/manual' => FakeResponse.new(
        '200',
        '{"dashboard_lists":[{"id":101,"name":"Generated Dashboards"}]}'
      ),
      '/api/v1/dashboard/lists/manual/101/dashboards' => FakeResponse.new(
        '200',
        '{"dashboards":[{"id":"abc123","title":"checkout-api SLO decision dashboard","url":"/dashboard/abc123"}]}'
      ),
      '/api/v1/dashboard/abc123' => FakeResponse.new(
        '200',
        '{"id":"abc123","title":"checkout-api SLO decision dashboard","description":"Generated dashboard for checkout-api from artifacts.dashboards[0]","layout_type":"ordered","tags":["managed_by:slo-rules-engine","service:checkout-api"],"template_variables":[{"name":"service","prefix":"service","default":"checkout-api"}],"widgets":[{"definition":{"type":"note","content":"Investigate request latency, traffic, and burn rate before paging."}}]}'
      )
    )
    client = SloRulesEngine::Datadog::Client.new(
      api_key: 'api-key',
      app_key: 'app-key',
      http: http,
      sleep_fn: ->(_seconds) {}
    )

    state = client.existing_state(
      desired: {
        slos: ['checkout-api http-requests public-api successful-requests'],
        monitors: ['SLO burn rate: checkout-api/http-requests/public-api/successful-requests'],
        dashboards: ['checkout-api SLO decision dashboard']
      }
    )

    assert_equal 'slo-123', state.fetch(:slos).fetch('checkout-api http-requests public-api successful-requests').fetch(:id)
    assert_equal 456, state.fetch(:monitors).fetch('SLO burn rate: checkout-api/http-requests/public-api/successful-requests').fetch(:id)
    assert_equal 'abc123', state.fetch(:dashboards).fetch('checkout-api SLO decision dashboard').fetch(:id)
    assert_equal 'name', state.fetch(:slos).fetch('checkout-api http-requests public-api successful-requests').fetch(:match_identity).fetch(:strategy)
    assert_equal 'medium', state.fetch(:slos).fetch('checkout-api http-requests public-api successful-requests').fetch(:match_identity).fetch(:confidence)
    assert_equal 'name', state.fetch(:monitors).fetch('SLO burn rate: checkout-api/http-requests/public-api/successful-requests').fetch(:match_identity).fetch(:strategy)
    assert_equal 'title', state.fetch(:dashboards).fetch('checkout-api SLO decision dashboard').fetch(:match_identity).fetch(:strategy)
    assert_equal 'metric',
                 state.fetch(:slos).fetch('checkout-api http-requests public-api successful-requests').fetch(:payload).fetch(:type)
    assert_equal 'slo alert',
                 state.fetch(:monitors).fetch('SLO burn rate: checkout-api/http-requests/public-api/successful-requests').fetch(:payload).fetch(:type)
    assert_equal 'ordered',
                 state.fetch(:dashboards).fetch('checkout-api SLO decision dashboard').fetch(:payload).fetch(:layout_type)
    assert_includes state.fetch(:dashboards).fetch('checkout-api SLO decision dashboard').fetch(:payload).fetch(:tags),
                    'managed_by:slo-rules-engine'
  end


  def test_datadog_client_ignores_unmanaged_slo_name_fallback_match
    http = RoutingHttp.new(
      '/api/v1/slo/search?page%5Bnumber%5D=0&page%5Bsize%5D=20&query=checkout-api+http-requests+public-api+successful-requests' => FakeResponse.new(
        '200',
        '{"data":{"attributes":{"slos":[{"data":{"id":"slo-123","attributes":{"name":"checkout-api http-requests public-api successful-requests","all_tags":["service:checkout-api"]}}}]}}}'
      )
    )
    client = SloRulesEngine::Datadog::Client.new(
      api_key: 'api-key',
      app_key: 'app-key',
      http: http,
      sleep_fn: ->(_seconds) {}
    )

    state = client.existing_state(
      desired: {
        slos: ['checkout-api http-requests public-api successful-requests']
      }
    )

    assert_empty state.fetch(:slos)
  end


  def test_datadog_client_ignores_unmanaged_dashboard_title_fallback_match
    http = RoutingHttp.new(
      '/api/v1/dashboard/lists/manual' => FakeResponse.new(
        '200',
        '{"dashboard_lists":[{"id":101,"name":"Generated Dashboards"}]}'
      ),
      '/api/v1/dashboard/lists/manual/101/dashboards' => FakeResponse.new(
        '200',
        '{"dashboards":[{"id":"abc123","title":"checkout-api SLO decision dashboard","url":"/dashboard/abc123"}]}'
      ),
      '/api/v1/dashboard/abc123' => FakeResponse.new(
        '200',
        '{"id":"abc123","title":"checkout-api SLO decision dashboard","layout_type":"ordered","tags":["service:checkout-api"]}'
      )
    )
    client = SloRulesEngine::Datadog::Client.new(
      api_key: 'api-key',
      app_key: 'app-key',
      http: http,
      sleep_fn: ->(_seconds) {}
    )

    state = client.existing_state(
      desired: {
        dashboards: ['checkout-api SLO decision dashboard']
      }
    )

    assert_empty state.fetch(:dashboards)
  end


  def test_datadog_client_matches_existing_state_by_source_tag_when_backend_names_drift
    desired_slo_name = @manifest.fetch(:artifacts).fetch(:slos).fetch(0).fetch(:name)
    desired_monitor_name = @manifest.fetch(:artifacts).fetch(:monitors).fetch(0).fetch(:name)
    desired_gap_name = @manifest.fetch(:artifacts).fetch(:telemetry_gap_monitors).fetch(0).fetch(:name)
    desired_dashboard_title = @manifest.fetch(:artifacts).fetch(:dashboards).fetch(0).fetch(:title)
    managed_tag = 'managed_by:slo-rules-engine'

    http = RoutingHttp.new(
      "/api/v1/slo/search?#{URI.encode_www_form('page[number]' => 0, 'page[size]' => 20, query: "#{managed_tag} AND source_ref:artifacts.slos.0")}" => FakeResponse.new(
        '200',
        '{"data":{"attributes":{"slos":[{"data":{"id":"slo-123","attributes":{"name":"legacy checkout slo","all_tags":["managed_by:slo-rules-engine","service:checkout-api","source_ref:artifacts.slos.0"]}}}]}}}'
      ),
      '/api/v1/slo/slo-123?with_configured_alert_ids=true' => FakeResponse.new(
        '200',
        '{"data":[{"id":"slo-123","name":"legacy checkout slo","type":"metric","description":"Generated by slo-rules-engine for checkout-api from artifacts.slos[0]","query":{"numerator":"count:http.server.request.duration{route:/checkout,service:checkout-api,status:success}.as_count()","denominator":"count:http.server.request.duration{route:/checkout,service:checkout-api}.as_count()"},"tags":["managed_by:slo-rules-engine","service:checkout-api","source_ref:artifacts.slos.0"],"thresholds":[{"timeframe":"30d","target":99.9}],"timeframe":"30d","target_threshold":99.9}]}'
      ),
      "/api/v1/monitor?#{URI.encode_www_form(monitor_tags: "#{managed_tag},source_ref:artifacts.monitors.0")}" => FakeResponse.new(
        '200',
        '[{"id":456,"name":"legacy burn monitor","tags":["managed_by:slo-rules-engine","service:checkout-api","source_ref:artifacts.monitors.0"]}]'
      ),
      '/api/v1/monitor/456' => FakeResponse.new(
        '200',
        '{"id":456,"name":"legacy burn monitor","type":"slo alert","query":"burn_rate(\"slo-123\").over(\"30d\").long_window(\"1h\").short_window(\"5m\") > 14.4","message":"Error budget burn is elevated for checkout-api http-requests public-api successful-requests.","tags":["managed_by:slo-rules-engine","service:checkout-api","route_key:checkout-api","source_ref:artifacts.monitors.0"],"options":{"include_tags":true,"thresholds":{"critical":14.4}}}'
      ),
      "/api/v1/monitor?#{URI.encode_www_form(monitor_tags: "#{managed_tag},source_ref:artifacts.telemetry_gap_monitors.0")}" => FakeResponse.new(
        '200',
        '[{"id":789,"name":"legacy telemetry gap monitor","tags":["managed_by:slo-rules-engine","service:checkout-api","source_ref:artifacts.telemetry_gap_monitors.0"]}]'
      ),
      '/api/v1/monitor/789' => FakeResponse.new(
        '200',
        '{"id":789,"name":"legacy telemetry gap monitor","type":"query alert","query":"avg(last_10m):count:http.server.request.duration{route:/checkout,service:checkout-api}.as_count() < 0","message":"Telemetry is missing for checkout-api http-requests public-api successful-requests.","tags":["managed_by:slo-rules-engine","service:checkout-api","route_key:checkout-api","source_ref:artifacts.telemetry_gap_monitors.0"],"options":{"include_tags":true,"notify_no_data":true,"no_data_timeframe":10,"thresholds":{"critical":0}}}'
      ),
      '/api/v1/dashboard/lists/manual' => FakeResponse.new(
        '200',
        '{"dashboard_lists":[{"id":101,"name":"Generated Dashboards"}]}'
      ),
      '/api/v1/dashboard/lists/manual/101/dashboards' => FakeResponse.new(
        '200',
        '{"dashboards":[{"id":"abc123","title":"legacy dashboard title","url":"/dashboard/abc123"}]}'
      ),
      '/api/v1/dashboard/abc123' => FakeResponse.new(
        '200',
        '{"id":"abc123","title":"legacy dashboard title","description":"Generated dashboard for checkout-api from artifacts.dashboards[0]","layout_type":"ordered","tags":["managed_by:slo-rules-engine","service:checkout-api","source_ref:artifacts.dashboards.0"],"template_variables":[{"name":"service","prefix":"service","default":"checkout-api"}],"widgets":[{"definition":{"type":"note","content":"Investigate request latency, traffic, and burn rate before paging."}}]}'
      )
    )
    client = SloRulesEngine::Datadog::Client.new(
      api_key: 'api-key',
      app_key: 'app-key',
      http: http,
      sleep_fn: ->(_seconds) {}
    )

    state = client.existing_state(
      desired: {
        slos: [{ name: desired_slo_name, source: 'artifacts.slos[0]' }],
        monitors: [
          { name: desired_monitor_name, source: 'artifacts.monitors[0]' },
          { name: desired_gap_name, source: 'artifacts.telemetry_gap_monitors[0]' }
        ],
        dashboards: [{ title: desired_dashboard_title, source: 'artifacts.dashboards[0]' }]
      }
    )

    assert_equal 'slo-123', state.fetch(:slos).fetch(desired_slo_name).fetch(:id)
    assert_equal 'legacy checkout slo', state.fetch(:slos).fetch(desired_slo_name).fetch(:payload).fetch(:name)
    assert_equal 'source_ref', state.fetch(:slos).fetch(desired_slo_name).fetch(:match_identity).fetch(:strategy)
    assert_equal 'high', state.fetch(:slos).fetch(desired_slo_name).fetch(:match_identity).fetch(:confidence)
    assert_equal 456, state.fetch(:monitors).fetch(desired_monitor_name).fetch(:id)
    assert_equal 'legacy burn monitor', state.fetch(:monitors).fetch(desired_monitor_name).fetch(:payload).fetch(:name)
    assert_equal 'source_ref', state.fetch(:monitors).fetch(desired_monitor_name).fetch(:match_identity).fetch(:strategy)
    assert_equal 789, state.fetch(:monitors).fetch(desired_gap_name).fetch(:id)
    assert_equal 'legacy telemetry gap monitor', state.fetch(:monitors).fetch(desired_gap_name).fetch(:payload).fetch(:name)
    assert_equal 'abc123', state.fetch(:dashboards).fetch(desired_dashboard_title).fetch(:id)
    assert_equal 'legacy dashboard title', state.fetch(:dashboards).fetch(desired_dashboard_title).fetch(:payload).fetch(:title)
    assert_equal 'source_ref', state.fetch(:dashboards).fetch(desired_dashboard_title).fetch(:match_identity).fetch(:strategy)
  end


  def test_datadog_client_marks_duplicate_source_ref_slo_matches_as_weak
    desired_slo_name = @manifest.fetch(:artifacts).fetch(:slos).fetch(0).fetch(:name)
    managed_tag = 'managed_by:slo-rules-engine'

    http = RoutingHttp.new(
      "/api/v1/slo/search?#{URI.encode_www_form('page[number]' => 0, 'page[size]' => 20, query: "#{managed_tag} AND source_ref:artifacts.slos.0")}" => FakeResponse.new(
        '200',
        '{"data":{"attributes":{"slos":[{"data":{"id":"slo-123","attributes":{"name":"legacy checkout slo a","all_tags":["managed_by:slo-rules-engine","service:checkout-api","source_ref:artifacts.slos.0"]}}},{"data":{"id":"slo-456","attributes":{"name":"legacy checkout slo b","all_tags":["managed_by:slo-rules-engine","service:checkout-api","source_ref:artifacts.slos.0"]}}}]}}}'
      ),
      '/api/v1/slo/slo-123?with_configured_alert_ids=true' => FakeResponse.new(
        '200',
        '{"data":[{"id":"slo-123","name":"legacy checkout slo a","type":"metric","description":"Generated by slo-rules-engine for checkout-api from artifacts.slos[0]","query":{"numerator":"count:http.server.request.duration{route:/checkout,service:checkout-api,status:success}.as_count()","denominator":"count:http.server.request.duration{route:/checkout,service:checkout-api}.as_count()"},"tags":["managed_by:slo-rules-engine","service:checkout-api","source_ref:artifacts.slos.0"],"thresholds":[{"timeframe":"30d","target":99.9}],"timeframe":"30d","target_threshold":99.9}]}'
      )
    )
    client = SloRulesEngine::Datadog::Client.new(
      api_key: 'api-key',
      app_key: 'app-key',
      http: http,
      sleep_fn: ->(_seconds) {}
    )

    state = client.existing_state(
      desired: {
        slos: [{ name: desired_slo_name, source: 'artifacts.slos[0]' }]
      }
    )

    assert_equal 'ambiguous_source_ref',
                 state.fetch(:slos).fetch(desired_slo_name).fetch(:match_identity).fetch(:strategy)
    assert_equal 'low',
                 state.fetch(:slos).fetch(desired_slo_name).fetch(:match_identity).fetch(:confidence)
  end


  def test_datadog_client_marks_duplicate_source_ref_monitor_matches_as_weak
    desired_monitor_name = @manifest.fetch(:artifacts).fetch(:monitors).fetch(0).fetch(:name)
    managed_tag = 'managed_by:slo-rules-engine'

    http = RoutingHttp.new(
      "/api/v1/monitor?#{URI.encode_www_form(monitor_tags: "#{managed_tag},source_ref:artifacts.monitors.0")}" => FakeResponse.new(
        '200',
        '[{"id":456,"name":"legacy burn monitor a","tags":["managed_by:slo-rules-engine","service:checkout-api","source_ref:artifacts.monitors.0"]},{"id":789,"name":"legacy burn monitor b","tags":["managed_by:slo-rules-engine","service:checkout-api","source_ref:artifacts.monitors.0"]}]'
      ),
      '/api/v1/monitor/456' => FakeResponse.new(
        '200',
        '{"id":456,"name":"legacy burn monitor a","type":"slo alert","query":"burn_rate(\"slo-123\").over(\"30d\").long_window(\"1h\").short_window(\"5m\") > 14.4","message":"Error budget burn is elevated for checkout-api http-requests public-api successful-requests.","tags":["managed_by:slo-rules-engine","service:checkout-api","route_key:checkout-api","source_ref:artifacts.monitors.0"],"options":{"include_tags":true,"thresholds":{"critical":14.4}}}'
      )
    )
    client = SloRulesEngine::Datadog::Client.new(
      api_key: 'api-key',
      app_key: 'app-key',
      http: http,
      sleep_fn: ->(_seconds) {}
    )

    state = client.existing_state(
      desired: {
        monitors: [{ name: desired_monitor_name, source: 'artifacts.monitors[0]' }]
      }
    )

    assert_equal 'ambiguous_source_ref',
                 state.fetch(:monitors).fetch(desired_monitor_name).fetch(:match_identity).fetch(:strategy)
    assert_equal 'low',
                 state.fetch(:monitors).fetch(desired_monitor_name).fetch(:match_identity).fetch(:confidence)
  end


  def test_datadog_client_marks_duplicate_source_ref_dashboard_matches_as_weak
    desired_dashboard_title = @manifest.fetch(:artifacts).fetch(:dashboards).fetch(0).fetch(:title)

    http = RoutingHttp.new(
      '/api/v1/dashboard/lists/manual' => FakeResponse.new(
        '200',
        '{"dashboard_lists":[{"id":101,"name":"Generated Dashboards"}]}'
      ),
      '/api/v1/dashboard/lists/manual/101/dashboards' => FakeResponse.new(
        '200',
        '{"dashboards":[{"id":"abc123","title":"legacy dashboard a","url":"/dashboard/abc123"},{"id":"def456","title":"legacy dashboard b","url":"/dashboard/def456"}]}'
      ),
      '/api/v1/dashboard/abc123' => FakeResponse.new(
        '200',
        '{"id":"abc123","title":"legacy dashboard a","layout_type":"ordered","tags":["managed_by:slo-rules-engine","service:checkout-api","source_ref:artifacts.dashboards.0"]}'
      ),
      '/api/v1/dashboard/def456' => FakeResponse.new(
        '200',
        '{"id":"def456","title":"legacy dashboard b","layout_type":"ordered","tags":["managed_by:slo-rules-engine","service:checkout-api","source_ref:artifacts.dashboards.0"]}'
      )
    )
    client = SloRulesEngine::Datadog::Client.new(
      api_key: 'api-key',
      app_key: 'app-key',
      http: http,
      sleep_fn: ->(_seconds) {}
    )

    state = client.existing_state(
      desired: {
        dashboards: [{ title: desired_dashboard_title, source: 'artifacts.dashboards[0]' }]
      }
    )

    assert_equal 'ambiguous_source_ref',
                 state.fetch(:dashboards).fetch(desired_dashboard_title).fetch(:match_identity).fetch(:strategy)
    assert_equal 'low',
                 state.fetch(:dashboards).fetch(desired_dashboard_title).fetch(:match_identity).fetch(:confidence)
  end


  def test_datadog_diff_flags_weaker_name_based_identity_matches
    slo_name = @manifest.fetch(:artifacts).fetch(:slos).fetch(0).fetch(:name)
    monitor_name = @manifest.fetch(:artifacts).fetch(:monitors).fetch(0).fetch(:name)
    gap_monitor_name = @manifest.fetch(:artifacts).fetch(:telemetry_gap_monitors).fetch(0).fetch(:name)
    dashboard_title = @manifest.fetch(:artifacts).fetch(:dashboards).fetch(0).fetch(:title)
    client = FakeDatadogClient.new(
      slos: {
        slo_name => {
          id: 'slo-123',
          payload: SloRulesEngine::Appliers::Datadog.new(client: FakeDatadogClient.new).plan(@manifest).operations.fetch(0).payload,
          match_identity: { strategy: 'name', confidence: 'medium' }
        }
      },
      monitors: {
        monitor_name => {
          id: 456,
          payload: SloRulesEngine::Appliers::Datadog.new(client: FakeDatadogClient.new).plan(@manifest).operations.fetch(1).payload.merge(
            query: SloRulesEngine::Appliers::Datadog.new(client: FakeDatadogClient.new).plan(@manifest).operations.fetch(1).payload.fetch(:query).sub(/__SLO_REF__\[.*?\]/, 'slo-123')
          ),
          match_identity: { strategy: 'name', confidence: 'medium' }
        },
        gap_monitor_name => {
          id: 789,
          payload: SloRulesEngine::Appliers::Datadog.new(client: FakeDatadogClient.new).plan(@manifest).operations.fetch(2).payload,
          match_identity: { strategy: 'source_ref', confidence: 'high' }
        }
      },
      dashboards: {
        dashboard_title => {
          id: 'dashboard-123',
          payload: SloRulesEngine::Appliers::Datadog.new(client: FakeDatadogClient.new).plan(@manifest).operations.fetch(3).payload,
          match_identity: { strategy: 'title', confidence: 'medium' }
        }
      }
    )
    applier = SloRulesEngine::Appliers::Datadog.new(client: client)

    plan = applier.diff(@manifest)

    assert_equal 'medium', plan.operations.fetch(0).risk.fetch(:level)
    assert_includes plan.operations.fetch(0).risk.fetch(:reasons), 'matched_without_source_ref'
    assert_equal({ strategy: 'name', confidence: 'medium' }, plan.operations.fetch(0).match_identity)
    assert_equal({ strategy: 'title', confidence: 'medium' }, plan.operations.fetch(3).match_identity)
    assert_equal 3, plan.to_h.fetch(:summary).fetch(:risky_operations)
  end


  def test_datadog_import_reports_weaker_identity_match_findings
    manifest = Marshal.load(Marshal.dump(@manifest))
    slo_name = manifest.fetch(:artifacts).fetch(:slos).fetch(0).fetch(:name)
    monitor_name = manifest.fetch(:artifacts).fetch(:monitors).fetch(0).fetch(:name)
    gap_monitor_name = manifest.fetch(:artifacts).fetch(:telemetry_gap_monitors).fetch(0).fetch(:name)
    dashboard_title = manifest.fetch(:artifacts).fetch(:dashboards).fetch(0).fetch(:title)
    client = FakeDatadogClient.new(
      slos: {
        slo_name => { id: 'slo-123', payload: { name: slo_name }, match_identity: { strategy: 'name', confidence: 'medium' } }
      },
      monitors: {
        monitor_name => { id: 456, payload: { name: monitor_name }, match_identity: { strategy: 'name', confidence: 'medium' } },
        gap_monitor_name => { id: 789, payload: { name: gap_monitor_name }, match_identity: { strategy: 'source_ref', confidence: 'high' } }
      },
      dashboards: {
        dashboard_title => { id: 'dashboard-123', payload: { title: dashboard_title }, match_identity: { strategy: 'title', confidence: 'medium' } }
      },
      managed_state: { slos: [], monitors: [], dashboards: [] }
    )
    applier = SloRulesEngine::Appliers::Datadog.new(client: client)

    imported = applier.import(manifest)

    findings = imported.findings.select { |entry| entry.fetch(:code) == 'weak_identity_match' }
    assert_equal 3, findings.length
    assert_equal ['datadog.dashboard', 'datadog.monitor', 'datadog.slo'], findings.map { |entry| entry.fetch(:target) }.sort
  end


  def test_datadog_client_lists_managed_resources_for_service
    http = RoutingHttp.new(
      '/api/v1/slo/search?page%5Bnumber%5D=0&page%5Bsize%5D=100&query=managed_by%3Aslo-rules-engine+AND+service%3Acheckout-api' => FakeResponse.new(
        '200',
        '{"data":{"attributes":{"slos":[{"data":{"id":"slo-123","attributes":{"name":"checkout-api http-requests public-api successful-requests","all_tags":["managed_by:slo-rules-engine","service:checkout-api"]}}},{"data":{"id":"slo-999","attributes":{"name":"checkout-api orphan slo","all_tags":["managed_by:slo-rules-engine","service:checkout-api"]}}}]}},"meta":{"pagination":{"total":2,"number":0,"last_number":0}}}'
      ),
      '/api/v1/monitor?monitor_tags=managed_by%3Aslo-rules-engine%2Cservice%3Acheckout-api' => FakeResponse.new(
        '200',
        '[{"id":456,"name":"SLO burn rate: checkout-api/http-requests/public-api/successful-requests","tags":["managed_by:slo-rules-engine","service:checkout-api"]},{"id":999,"name":"SLO burn rate: checkout-api/orphan-sli/orphan-instance/orphan-slo","tags":["managed_by:slo-rules-engine","service:checkout-api"]}]'
      ),
      '/api/v1/dashboard/lists/manual' => FakeResponse.new(
        '200',
        '{"dashboard_lists":[{"id":101,"name":"Generated Dashboards"}]}'
      ),
      '/api/v1/dashboard/lists/manual/101/dashboards' => FakeResponse.new(
        '200',
        '{"dashboards":[{"id":"abc123","title":"checkout-api SLO decision dashboard","url":"/dashboard/abc123"},{"id":"def456","title":"checkout-api orphan dashboard","url":"/dashboard/def456"},{"id":"zzz999","title":"other-service SLO decision dashboard","url":"/dashboard/zzz999"}]}'
      ),
      '/api/v1/dashboard/abc123' => FakeResponse.new(
        '200',
        '{"id":"abc123","title":"checkout-api SLO decision dashboard","layout_type":"ordered","tags":["managed_by:slo-rules-engine","service:checkout-api"]}'
      ),
      '/api/v1/dashboard/def456' => FakeResponse.new(
        '200',
        '{"id":"def456","title":"checkout-api orphan dashboard","layout_type":"ordered","tags":["managed_by:slo-rules-engine","service:checkout-api"]}'
      ),
      '/api/v1/dashboard/zzz999' => FakeResponse.new(
        '200',
        '{"id":"zzz999","title":"other-service SLO decision dashboard","layout_type":"ordered","tags":["managed_by:slo-rules-engine","service:other-service"]}'
      )
    )
    client = SloRulesEngine::Datadog::Client.new(
      api_key: 'api-key',
      app_key: 'app-key',
      http: http,
      sleep_fn: ->(_seconds) {}
    )

    state = client.managed_state(service: 'checkout-api')

    assert_equal ['checkout-api http-requests public-api successful-requests', 'checkout-api orphan slo'],
                 state.fetch(:slos).map { |entry| entry.fetch(:name) }
    assert_equal [456, 999], state.fetch(:monitors).map { |entry| entry.fetch(:id) }
    assert_equal %w[checkout-api\ SLO\ decision\ dashboard checkout-api\ orphan\ dashboard],
                 state.fetch(:dashboards).map { |entry| entry.fetch(:title) }
  end


  def test_datadog_diff_ignores_backend_only_fields_from_live_imported_state
    desired_operations = SloRulesEngine::Appliers::Datadog.new(client: FakeDatadogClient.new).plan(@manifest).operations
    slo_name = desired_operations.fetch(0).name
    burn_monitor_name = desired_operations.fetch(1).name
    gap_monitor_name = desired_operations.fetch(2).name
    dashboard_title = desired_operations.fetch(3).name
    slo_payload = Marshal.load(Marshal.dump(desired_operations.fetch(0).payload))
    burn_payload = Marshal.load(Marshal.dump(desired_operations.fetch(1).payload))
    burn_payload[:query] = burn_payload.fetch(:query).sub(/__SLO_REF__\[.*?\]/, 'slo-123')
    gap_payload = Marshal.load(Marshal.dump(desired_operations.fetch(2).payload))
    dashboard_payload = Marshal.load(Marshal.dump(desired_operations.fetch(3).payload))

    http = RoutingHttp.new(
      "/api/v1/slo/search?#{URI.encode_www_form('page[number]' => 0, 'page[size]' => 20, query: 'managed_by:slo-rules-engine AND source_ref:artifacts.slos.0')}" => FakeResponse.new(
        '200',
        JSON.generate(
          data: {
            attributes: {
              slos: [
                {
                  data: {
                    id: 'slo-123',
                    attributes: {
                      name: slo_name,
                      all_tags: ['managed_by:slo-rules-engine', 'source_ref:artifacts.slos.0']
                    }
                  }
                }
              ]
            }
          },
          meta: { pagination: { total: 1, number: 0, last_number: 0 } }
        )
      ),
      "/api/v1/slo/search?#{URI.encode_www_form('page[number]' => 0, 'page[size]' => 20, query: slo_name)}" => FakeResponse.new(
        '200',
        JSON.generate(
          data: {
            attributes: {
              slos: [
                {
                  data: {
                    id: 'slo-123',
                    attributes: {
                      name: slo_name,
                      all_tags: ['managed_by:slo-rules-engine']
                    }
                  }
                }
              ]
            }
          },
          meta: { pagination: { total: 1, number: 0, last_number: 0 } }
        )
      ),
      '/api/v1/slo/slo-123?with_configured_alert_ids=true' => FakeResponse.new(
        '200',
        JSON.generate(
          data: [
            slo_payload.merge(
              id: 'slo-123',
              modified_at: '2026-05-03T10:00:00Z',
              monitor_ids: [456],
              creator: { email: 'bot@example.com' },
              tags: slo_payload.fetch(:tags) + ['env:prod']
            )
          ]
        )
      ),
      "/api/v1/monitor?#{URI.encode_www_form(monitor_tags: 'managed_by:slo-rules-engine,source_ref:artifacts.monitors.0')}" => FakeResponse.new(
        '200',
        JSON.generate([{ id: 456, name: burn_monitor_name, tags: ['managed_by:slo-rules-engine', 'source_ref:artifacts.monitors.0'] }])
      ),
      "/api/v1/monitor?#{URI.encode_www_form(monitor_tags: 'managed_by:slo-rules-engine', name: burn_monitor_name)}" => FakeResponse.new(
        '200',
        JSON.generate([{ id: 456, name: burn_monitor_name, tags: ['managed_by:slo-rules-engine'] }])
      ),
      '/api/v1/monitor/456' => FakeResponse.new(
        '200',
        JSON.generate(
          burn_payload.merge(
            id: 456,
            overall_state: 'OK',
            creator: { email: 'bot@example.com' },
            tags: burn_payload.fetch(:tags) + ['env:prod'],
            options: burn_payload.fetch(:options).merge(evaluation_delay: 300)
          )
        )
      ),
      "/api/v1/monitor?#{URI.encode_www_form(monitor_tags: 'managed_by:slo-rules-engine,source_ref:artifacts.telemetry_gap_monitors.0')}" => FakeResponse.new(
        '200',
        JSON.generate([{ id: 789, name: gap_monitor_name, tags: ['managed_by:slo-rules-engine', 'source_ref:artifacts.telemetry_gap_monitors.0'] }])
      ),
      "/api/v1/monitor?#{URI.encode_www_form(monitor_tags: 'managed_by:slo-rules-engine', name: gap_monitor_name)}" => FakeResponse.new(
        '200',
        JSON.generate([{ id: 789, name: gap_monitor_name, tags: ['managed_by:slo-rules-engine'] }])
      ),
      '/api/v1/monitor/789' => FakeResponse.new(
        '200',
        JSON.generate(
          gap_payload.merge(
            id: 789,
            overall_state: 'OK',
            creator: { email: 'bot@example.com' },
            tags: gap_payload.fetch(:tags) + ['env:prod'],
            options: gap_payload.fetch(:options).merge(groupby_simple_monitor: false)
          )
        )
      ),
      '/api/v1/dashboard/lists/manual' => FakeResponse.new(
        '200',
        JSON.generate(dashboard_lists: [{ id: 101, name: 'Generated Dashboards' }])
      ),
      '/api/v1/dashboard/lists/manual/101/dashboards' => FakeResponse.new(
        '200',
        JSON.generate(dashboards: [{ id: 'abc123', title: dashboard_title, url: '/dashboard/abc123' }])
      ),
      '/api/v1/dashboard/abc123' => FakeResponse.new(
        '200',
        JSON.generate(
          dashboard_payload.merge(
            id: 'abc123',
            author_handle: 'bot@datadog',
            tags: dashboard_payload.fetch(:tags) + ['env:prod'],
            notify_list: [],
            widgets: dashboard_payload.fetch(:widgets).each_with_index.map do |widget, index|
              widget.merge(id: index + 1, layout: { x: 0, y: index * 2, width: 47, height: 6 })
            end
          )
        )
      )
    )
    client = SloRulesEngine::Datadog::Client.new(
      api_key: 'api-key',
      app_key: 'app-key',
      http: http,
      sleep_fn: ->(_seconds) {}
    )
    applier = SloRulesEngine::Appliers::Datadog.new(client: client)

    plan = applier.diff(@manifest)

    assert_equal %w[noop noop noop noop], plan.operations.map(&:action)
  end

end
