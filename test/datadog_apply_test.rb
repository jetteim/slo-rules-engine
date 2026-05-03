# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/slo_rules_engine'

class DatadogApplyTest < Minitest::Test
  def setup
    SloRulesEngine.clear_definitions
    load File.expand_path('../examples/services/checkout.rb', __dir__)
    @definition = SloRulesEngine.definitions.fetch(0)
    @manifest = SloRulesEngine.default_provider_registry.fetch('datadog')
      .generate(@definition)
      .to_h
      .merge(service: @definition.service)
  end

  def test_datadog_applier_plans_slos_monitors_gap_monitors_and_dashboards
    applier = SloRulesEngine::Appliers::Datadog.new(client: FakeDatadogClient.new)

    plan = applier.plan(@manifest)

    assert_equal 'datadog', plan.provider
    assert_equal 'dry_run', plan.mode
    assert_equal %w[create create create create], plan.operations.map(&:action)
    assert_equal ['datadog.slo', 'datadog.monitor', 'datadog.monitor', 'datadog.dashboard'], plan.operations.map(&:target)
    assert_equal ['artifacts.slos[0]', 'artifacts.monitors[0]', 'artifacts.telemetry_gap_monitors[0]', 'artifacts.dashboards[0]'], plan.operations.map(&:source)
  end

  def test_datadog_applier_uses_backend_state_to_plan_updates
    slo_name = @manifest.fetch(:artifacts).fetch(:slos).fetch(0).fetch(:name)
    monitor_name = @manifest.fetch(:artifacts).fetch(:monitors).fetch(0).fetch(:name)
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
    assert_equal [slo_name], client.existing_state_requests.fetch(0).fetch(:slos)
    assert_equal [monitor_name, @manifest.fetch(:artifacts).fetch(:telemetry_gap_monitors).fetch(0).fetch(:name)],
                 client.existing_state_requests.fetch(0).fetch(:monitors)
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
    assert_equal [slo_name], client.existing_state_requests.fetch(0).fetch(:slos)
    assert_equal [monitor_name, @manifest.fetch(:artifacts).fetch(:telemetry_gap_monitors).fetch(0).fetch(:name)],
                 client.existing_state_requests.fetch(0).fetch(:monitors)
  end

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

    slo_payload = client.requests.fetch(0).fetch(:payload)
    assert_equal 'metric', slo_payload.fetch(:type)
    assert_equal 'checkout-api http-requests public-api successful-requests', slo_payload.fetch(:name)
    assert_equal '30d', slo_payload.fetch(:timeframe)
    assert_equal 99.9, slo_payload.fetch(:target_threshold)
    assert_equal 'count:http.server.request.duration{route:/checkout,service:checkout-api,status:success}.as_count()',
                 slo_payload.fetch(:query).fetch(:numerator)
    assert_equal 'count:http.server.request.duration{route:/checkout,service:checkout-api}.as_count()',
                 slo_payload.fetch(:query).fetch(:denominator)

    burn_rate_payload = client.requests.fetch(1).fetch(:payload)
    assert_equal 'slo alert', burn_rate_payload.fetch(:type)
    assert_includes burn_rate_payload.fetch(:query), 'burn_rate("generated-slo-1").over("30d").long_window("1h").short_window("5m") > 14.4'
    assert_equal 14.4, burn_rate_payload.fetch(:options).fetch(:thresholds).fetch(:critical)

    telemetry_gap_payload = client.requests.fetch(2).fetch(:payload)
    assert_equal 'query alert', telemetry_gap_payload.fetch(:type)
    assert_equal true, telemetry_gap_payload.fetch(:options).fetch(:notify_no_data)
    assert_includes telemetry_gap_payload.fetch(:query), 'avg(last_10m):count:http.server.request.duration{route:/checkout,service:checkout-api}.as_count() < 0'

    dashboard_payload = client.requests.fetch(3).fetch(:payload)
    assert_equal 'ordered', dashboard_payload.fetch(:layout_type)
    assert_equal 'checkout-api SLO decision dashboard', dashboard_payload.fetch(:title)
    assert_equal %w[service sli sli_instance slo],
                 dashboard_payload.fetch(:template_variables).map { |variable| variable.fetch(:name) }
  end

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
        '{"id":"abc123","title":"checkout-api SLO decision dashboard","description":"Generated dashboard for checkout-api from artifacts.dashboards[0]","layout_type":"ordered","template_variables":[{"name":"service","prefix":"service","default":"checkout-api"}],"widgets":[{"definition":{"type":"note","content":"Investigate request latency, traffic, and burn rate before paging."}}]}'
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
    assert_equal 'metric',
                 state.fetch(:slos).fetch('checkout-api http-requests public-api successful-requests').fetch(:payload).fetch(:type)
    assert_equal 'slo alert',
                 state.fetch(:monitors).fetch('SLO burn rate: checkout-api/http-requests/public-api/successful-requests').fetch(:payload).fetch(:type)
    assert_equal 'ordered',
                 state.fetch(:dashboards).fetch('checkout-api SLO decision dashboard').fetch(:payload).fetch(:layout_type)
  end

  def test_datadog_live_apply_requires_credentials
    client = SloRulesEngine::Datadog::Client.new(api_key: nil, app_key: nil)

    assert_raises(SloRulesEngine::Datadog::MissingCredentials) do
      client.validate_credentials!
    end
  end

  def test_datadog_client_retries_transient_responses
    http = RetryHttp.new([
      FakeResponse.new('429', '{"errors":["rate limited"]}', 'Retry-After' => '0'),
      FakeResponse.new('200', '{"ok":true}')
    ])
    sleeps = []
    client = SloRulesEngine::Datadog::Client.new(
      api_key: 'api-key',
      app_key: 'app-key',
      http: http,
      sleep_fn: ->(seconds) { sleeps << seconds }
    )

    response = client.request('POST', '/api/v1/monitor', payload: { name: 'test' }, retries: 2)

    assert_equal({ 'ok' => true }, response)
    assert_equal [1], sleeps
    assert_equal 2, http.requests.length
    assert_equal '/api/v1/monitor', http.requests.fetch(0).path
  end

  def test_datadog_client_uses_rate_limit_reset_delay
    http = RetryHttp.new([
      FakeResponse.new('429', '{"errors":["rate limited"]}', 'X-RateLimit-Reset' => '7'),
      FakeResponse.new('200', '{"ok":true}')
    ])
    sleeps = []
    client = SloRulesEngine::Datadog::Client.new(
      api_key: 'api-key',
      app_key: 'app-key',
      http: http,
      sleep_fn: ->(seconds) { sleeps << seconds }
    )

    client.request('GET', '/api/v1/query?from=1&to=2&query=up', retries: 2)

    assert_equal [7], sleeps
  end

  def test_datadog_client_uses_rate_limit_period_when_reset_is_absent
    http = RetryHttp.new([
      FakeResponse.new('429', '{"errors":["rate limited"]}', 'X-RateLimit-Period' => '11'),
      FakeResponse.new('200', '{"ok":true}')
    ])
    sleeps = []
    client = SloRulesEngine::Datadog::Client.new(
      api_key: 'api-key',
      app_key: 'app-key',
      http: http,
      sleep_fn: ->(seconds) { sleeps << seconds }
    )

    client.request('GET', '/api/v1/query?from=1&to=2&query=up', retries: 2)

    assert_equal [11], sleeps
  end

  private

  class FakeDatadogClient
    attr_reader :requests, :existing_state_requests

    def initialize(slos: {}, monitors: {}, dashboards: {})
      @state = { slos: slos, monitors: monitors, dashboards: dashboards }
      @requests = []
      @existing_state_requests = []
    end

    def existing_state(desired: nil)
      @existing_state_requests << desired
      @state
    end

    def validate_credentials!
      true
    end

    def request(method, path, payload: nil)
      @requests << { method: method, path: path, payload: payload }
      case path
      when '/api/v1/slo'
        { 'data' => [{ 'id' => 'generated-slo-1' }] }
      when '/api/v1/monitor'
        { 'id' => "monitor-#{@requests.length}" }
      when '/api/v1/dashboard'
        { 'id' => 'dashboard-1' }
      else
        { 'id' => "request-#{@requests.length}" }
      end
    end
  end

  class RetryHttp
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def start(_host, _port, use_ssl:)
      raise 'expected TLS for Datadog API' unless use_ssl

      yield self
    end

    def request(request)
      @requests << request
      @responses.shift
    end
  end

  class RoutingHttp
    def initialize(routes)
      @routes = routes
    end

    def start(_host, _port, use_ssl:)
      raise 'expected TLS for Datadog API' unless use_ssl

      yield self
    end

    def request(request)
      response = @routes.fetch(request.path) do
        raise "unexpected Datadog request path #{request.path}"
      end
      response
    end
  end

  class FakeResponse
    attr_reader :code, :body

    def initialize(code, body, headers = {})
      @code = code
      @body = body
      @headers = headers
    end

    def [](key)
      @headers[key]
    end
  end
end
