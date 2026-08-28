# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/slo_rules_engine'
require_relative 'support/datadog_fakes'

class DatadogRequestTransportTest < Minitest::Test
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

  def test_retries_transient_response_and_returns_parsed_body
    http = RetryHttp.new([
      FakeResponse.new('429', '{"errors":["rate limited"]}', 'Retry-After' => '0'),
      FakeResponse.new('200', '{"ok":true}')
    ])
    sleeps = []
    transport = SloRulesEngine::Datadog::RequestTransport.new(
      api_key: 'api-key',
      app_key: 'app-key',
      http: http,
      sleep_fn: ->(seconds) { sleeps << seconds }
    )

    response = transport.request('POST', '/api/v1/monitor', payload: { name: 'test' }, retries: 2)

    assert_equal({ 'ok' => true }, response)
    assert_equal [1], sleeps
    assert_equal 2, http.requests.length
    assert_equal '/api/v1/monitor', http.requests.fetch(0).path
    assert_equal 'api-key', http.requests.fetch(0)['DD-API-KEY']
    assert_equal '{"name":"test"}', http.requests.fetch(0).body
  end

  def test_rejects_oversized_response_before_json_parsing
    http = RetryHttp.new([FakeResponse.new('200', '{"secret":"provider text"}')])
    transport = SloRulesEngine::Datadog::RequestTransport.new(
      api_key: 'api-key',
      app_key: 'app-key',
      http: http,
      sleep_fn: ->(_seconds) {}
    )

    error = assert_raises(SloRulesEngine::Datadog::ApiError) do
      transport.request('GET', '/api/v1/metrics', max_response_bytes: 8)
    end

    assert_equal 'Datadog response exceeded the byte limit', error.message
    refute_includes error.message, 'provider text'
  end
end
