# frozen_string_literal: true

require_relative 'support/datadog_apply_test_case'

class DatadogApplyTest < Minitest::Test
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


  def test_datadog_client_uses_60_second_delay_for_transient_server_errors_without_headers
    http = RetryHttp.new([
      FakeResponse.new('500', '{"errors":["backend failed"]}'),
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

    assert_equal [60], sleeps
  end


  def test_datadog_client_retries_connection_reset
    http = ConnectionResetHttp.new([
      Errno::ECONNRESET,
      FakeResponse.new('200', '{"ok":true}')
    ])
    sleeps = []
    client = SloRulesEngine::Datadog::Client.new(
      api_key: 'api-key',
      app_key: 'app-key',
      http: http,
      sleep_fn: ->(seconds) { sleeps << seconds }
    )

    response = client.request('GET', '/api/v1/query?from=1&to=2&query=up', retries: 2)

    assert_equal({ 'ok' => true }, response)
    assert_equal 2, http.request_count
    assert_operator sleeps.fetch(0), :>, 0
  end


  def test_datadog_client_delete_slo_uses_force_query_and_ignores_not_found
    http = RoutingHttp.new(
      '/api/v1/slo/slo-123?force=true' => FakeResponse.new('404', '{"errors":["not found"]}')
    )
    client = SloRulesEngine::Datadog::Client.new(
      api_key: 'api-key',
      app_key: 'app-key',
      http: http,
      sleep_fn: ->(_seconds) {}
    )

    result = client.delete_slo('slo-123', force: true)

    assert_nil result
  end


  def test_datadog_client_delete_monitor_ignores_not_found
    http = RoutingHttp.new(
      '/api/v1/monitor/456' => FakeResponse.new('404', '{"errors":["not found"]}')
    )
    client = SloRulesEngine::Datadog::Client.new(
      api_key: 'api-key',
      app_key: 'app-key',
      http: http,
      sleep_fn: ->(_seconds) {}
    )

    result = client.delete_monitor(456)

    assert_nil result
  end


  def test_datadog_client_create_and_wait_for_slo_polls_until_resource_exists
    http = SequencedRoutingHttp.new(
      '/api/v1/slo' => [
        FakeResponse.new('200', '{"data":[{"id":"slo-123"}]}')
      ],
      '/api/v1/slo/slo-123' => [
        FakeResponse.new('404', '{"errors":["not ready"]}'),
        FakeResponse.new('200', '{"data":{"id":"slo-123"}}')
      ]
    )
    sleeps = []
    client = SloRulesEngine::Datadog::Client.new(
      api_key: 'api-key',
      app_key: 'app-key',
      http: http,
      sleep_fn: ->(seconds) { sleeps << seconds }
    )

    response = client.create_and_wait_slo(name: 'checkout')

    assert_equal 'slo-123', response.fetch('data').fetch(0).fetch('id')
    assert_equal [0.2], sleeps
  end


  def test_datadog_client_create_and_wait_for_monitor_polls_until_resource_exists
    http = SequencedRoutingHttp.new(
      '/api/v1/monitor' => [
        FakeResponse.new('200', '{"id":456,"name":"monitor"}')
      ],
      '/api/v1/monitor/456' => [
        FakeResponse.new('404', '{"errors":["not ready"]}'),
        FakeResponse.new('200', '{"id":456,"name":"monitor"}')
      ]
    )
    sleeps = []
    client = SloRulesEngine::Datadog::Client.new(
      api_key: 'api-key',
      app_key: 'app-key',
      http: http,
      sleep_fn: ->(seconds) { sleeps << seconds }
    )

    response = client.create_and_wait_monitor(name: 'monitor')

    assert_equal 456, response.fetch('id')
    assert_equal [0.2], sleeps
  end
end
