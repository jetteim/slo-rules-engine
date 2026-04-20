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
  end

  def test_datadog_apply_calls_api_paths_through_injected_client
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
    assert_equal 'artifacts.slos[0]', client.requests.fetch(0).fetch(:payload).fetch(:source)
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

  private

  class FakeDatadogClient
    attr_reader :requests

    def initialize(slos: {}, monitors: {}, dashboards: {})
      @state = { slos: slos, monitors: monitors, dashboards: dashboards }
      @requests = []
    end

    def existing_state
      @state
    end

    def validate_credentials!
      true
    end

    def request(method, path, payload: nil)
      @requests << { method: method, path: path, payload: payload }
      { 'id' => "request-#{@requests.length}" }
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
