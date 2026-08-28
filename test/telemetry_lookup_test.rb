# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/slo_rules_engine'

class TelemetryLookupTest < Minitest::Test
  def test_lookup_result_serializes_normalized_signals
    signal = SloRulesEngine::TelemetryLookup::Signal.new(
      kind: 'latency',
      metric: 'http.server.request.duration',
      user_visible: true,
      source: 'datadog'
    )
    result = SloRulesEngine::TelemetryLookup::Result.new(provider: 'datadog', signals: [signal], findings: [])

    payload = result.to_h

    assert_equal 'datadog', payload.fetch(:provider)
    assert_equal 'latency', payload.fetch(:signals).fetch(0).fetch(:kind)
    assert_equal 'http.server.request.duration', payload.fetch(:signals).fetch(0).fetch(:metric)
  end

  def test_datadog_lookup_uses_injected_client_and_records_series_count
    client = FakeDatadogLookupClient.new(
      '/api/v1/query?from=100&query=p95%3Ahttp.server.request.duration%7Bservice%3Acheckout-api%7D&to=200' => {
        'series' => [{ 'metric' => 'http.server.request.duration' }]
      }
    )
    lookup = SloRulesEngine::TelemetryLookup::Datadog.new(client: client, from: 100, to: 200)

    result = lookup.lookup(
      metric: 'http.server.request.duration',
      kind: 'latency',
      query: 'p95:http.server.request.duration{service:checkout-api}',
      user_visible: true
    )

    assert_empty result.findings
    signal = result.signals.fetch(0)
    assert_equal 'datadog', result.provider
    assert_equal 'datadog', signal.source
    assert_equal 1, signal.series_count
    assert_equal ['/api/v1/query?from=100&query=p95%3Ahttp.server.request.duration%7Bservice%3Acheckout-api%7D&to=200'], client.paths
  end

  def test_prometheus_lookup_reports_missing_series_as_finding
    client = FakePrometheusLookupClient.new(series: [], query_result: [])
    lookup = SloRulesEngine::TelemetryLookup::Prometheus.new(client: client, provider: 'prometheus_stack')

    result = lookup.lookup(metric: 'http_requests_total', kind: 'errors', user_visible: true)

    assert_empty result.signals
    finding = result.findings.fetch(0)
    assert_equal 'prometheus_stack', result.provider
    assert_equal 'missing_backend_series', finding.code
    assert_equal 'http_requests_total', finding.metric
    assert_equal ['http_requests_total'], client.series_selectors
  end

  def test_datadog_discovery_lists_active_metrics_and_classifies_signals
    client = FakeDatadogLookupClient.new(
      '/api/v1/metrics?from=100&tag_filter=service%3Acheckout-api' => {
        'metrics' => ['http.server.request.duration', 'runtime.heap.used']
      }
    )
    lookup = SloRulesEngine::TelemetryLookup::Datadog.new(client: client, from: 100, to: 200)

    result = lookup.discover(service: 'checkout-api')

    assert_empty result.findings
    assert_equal %w[latency saturation], result.signals.map(&:kind)
    assert_equal [true, false], result.signals.map(&:user_visible)
    assert_equal ['/api/v1/metrics?from=100&tag_filter=service%3Acheckout-api'], client.paths
  end

  def test_datadog_discovery_rejects_host_plus_service_filters
    lookup = SloRulesEngine::TelemetryLookup::Datadog.new(client: FakeDatadogLookupClient.new({}), from: 100, to: 200)

    error = assert_raises(ArgumentError) do
      lookup.discover(service: 'checkout-api', host: 'checkout-host')
    end

    assert_includes error.message, 'cannot combine host'
  end

  def test_prometheus_discovery_uses_metric_name_label_values
    client = FakePrometheusLookupClient.new(
      series: [],
      query_result: [],
      label_values: %w[http_server_request_duration_seconds_count runtime_heap_used]
    )
    lookup = SloRulesEngine::TelemetryLookup::Prometheus.new(client: client, provider: 'prometheus_stack')

    result = lookup.discover(service: 'checkout-api')

    assert_empty result.findings
    assert_equal %w[latency saturation], result.signals.map(&:kind)
    assert_equal ['{service="checkout-api"}'], client.label_value_matchers
  end

  def test_prometheus_client_encodes_query_parameters_exactly_once
    http = CapturingPrometheusHttp.new
    client = SloRulesEngine::TelemetryLookup::Prometheus::Client.new(
      base_url: 'http://prometheus.test:9090',
      http: http
    )
    expression = 'sum(rate(http_requests_total{service="checkout"}[5m]))'

    client.query(expression)

    uri = http.uris.fetch(0)
    assert_equal '/api/v1/query', uri.path
    assert_equal [['query', expression]], URI.decode_www_form(uri.query)
    assert_includes uri.query, '%5B5m%5D'
    refute_includes uri.query, '%255B5m%255D'
  end

  def test_prometheus_client_rejects_unsafe_dynamic_label_path_segments_before_http
    http = CapturingPrometheusHttp.new
    client = SloRulesEngine::TelemetryLookup::Prometheus::Client.new(
      base_url: 'http://prometheus.test:9090',
      http: http
    )

    error = assert_raises(ArgumentError) do
      client.label_values('__name__%2Fvalues')
    end

    assert_includes error.message, 'unsafe Prometheus label name'
    assert_empty http.uris
  end

  private

  class FakeDatadogLookupClient
    attr_reader :paths

    def initialize(responses)
      @responses = responses
      @paths = []
    end

    def request(method, path, payload: nil, max_response_bytes: nil)
      raise "unexpected payload #{payload.inspect}" if payload
      raise "unexpected method #{method}" unless method == 'GET'
      raise "missing response bound" unless max_response_bytes == 2_097_152

      @paths << path
      @responses.fetch(path)
    end
  end

  class FakePrometheusLookupClient
    attr_reader :series_selectors, :queries, :label_value_matchers

    def initialize(series:, query_result:, label_values: [])
      @series = series
      @query_result = query_result
      @label_values = label_values
      @series_selectors = []
      @queries = []
      @label_value_matchers = []
    end

    def series(selector)
      @series_selectors << selector
      @series
    end

    def query(expression)
      @queries << expression
      { 'result' => @query_result }
    end

    def label_values(label_name, matchers: [])
      raise "unexpected label name #{label_name}" unless label_name == '__name__'

      @label_value_matchers.concat(matchers)
      @label_values
    end
  end

  class CapturingPrometheusHttp
    Response = Struct.new(:body)
    attr_reader :uris

    def initialize
      @uris = []
    end

    def get_response(uri)
      @uris << uri
      Response.new(JSON.generate(status: 'success', data: { result: [] }))
    end
  end
end
