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

  private

  class FakeDatadogLookupClient
    attr_reader :paths

    def initialize(responses)
      @responses = responses
      @paths = []
    end

    def request(method, path, payload: nil)
      raise "unexpected payload #{payload.inspect}" if payload
      raise "unexpected method #{method}" unless method == 'GET'

      @paths << path
      @responses.fetch(path)
    end
  end

  class FakePrometheusLookupClient
    attr_reader :series_selectors, :queries

    def initialize(series:, query_result:)
      @series = series
      @query_result = query_result
      @series_selectors = []
      @queries = []
    end

    def series(selector)
      @series_selectors << selector
      @series
    end

    def query(expression)
      @queries << expression
      { 'result' => @query_result }
    end
  end
end
