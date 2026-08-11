# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/slo_rules_engine'
require_relative 'support/sloth_mcp_fixtures'

class SlothMcpClientTest < Minitest::Test
  include SlothMcpFixtures

  class FakeTransport
    Response = SloRulesEngine::Sloth::Mcp::RequestTransport::Response

    attr_reader :requests

    def initialize(tools:, rpc_error: false, oversized: false)
      @tools = tools
      @rpc_error = rpc_error
      @oversized = oversized
      @requests = []
    end

    def post(_uri, payload, protocol_version:, timeout_seconds:, max_response_bytes:)
      requests << {
        payload: payload,
        protocol_version: protocol_version,
        timeout_seconds: timeout_seconds,
        max_response_bytes: max_response_bytes
      }
      return Response.new(status: 202, body: '') unless payload[:id]

      result = case payload.fetch(:method)
               when 'initialize'
                 {
                   protocolVersion: SlothMcpFixtures::MCP_PROTOCOL_VERSION,
                   serverInfo: { name: 'sloth', version: SlothMcpFixtures::MCP_VERSION },
                   capabilities: { tools: {} }
                 }
               when 'tools/list'
                 { tools: @tools }
               when 'tools/call'
                 { structuredContent: { version: SlothMcpFixtures::MCP_VERSION, description: 'discarded' } }
               end
      envelope = if @rpc_error && payload.fetch(:method) == 'tools/call'
                   {
                     jsonrpc: '2.0', id: payload.fetch(:id),
                     error: { code: -32_000, message: 'secret raw backend error' }
                   }
                 else
                   { jsonrpc: '2.0', id: payload.fetch(:id), result: result }
                 end
      body = @oversized ? ('x' * (max_response_bytes + 1)) : JSON.generate(envelope)
      Response.new(status: 200, body: body)
    end
  end

  def test_initializes_lists_tools_and_calls_only_structured_results
    transport = FakeTransport.new(tools: sloth_mcp_tools)
    client = SloRulesEngine::Sloth::Mcp::Client.new(config: runtime_config, transport: transport)

    connection = client.connect
    result = client.call_tool('context')

    assert_equal MCP_PROTOCOL_VERSION, connection.fetch(:protocol_version)
    assert_equal({ name: 'sloth', version: MCP_VERSION }, connection.fetch(:server_info))
    assert_equal MCP_VERSION, result.fetch('version')
    assert_equal %w[initialize notifications/initialized tools/list tools/call],
                 transport.requests.map { |request| request.dig(:payload, :method) }
    assert_nil transport.requests.fetch(0).fetch(:protocol_version)
    transport.requests.drop(1).each do |request|
      assert_equal MCP_PROTOCOL_VERSION, request.fetch(:protocol_version)
      assert_equal 10, request.fetch(:timeout_seconds)
      assert_equal 1_048_576, request.fetch(:max_response_bytes)
    end


    error = assert_raises(SloRulesEngine::Sloth::Mcp::ContractError) do
      client.call_tool('mutate_slo')
    end
    assert_equal 'unsafe_sloth_mcp_tool', error.code
    assert_equal 4, transport.requests.length
  end

  def test_sanitizes_rpc_errors_and_rejects_oversized_responses
    transport = FakeTransport.new(tools: sloth_mcp_tools, rpc_error: true)
    client = SloRulesEngine::Sloth::Mcp::Client.new(config: runtime_config, transport: transport)
    client.connect

    error = assert_raises(SloRulesEngine::Sloth::Mcp::ContractError) do
      client.call_tool('context')
    end
    assert_equal 'sloth_mcp_rpc_error', error.code
    refute_includes JSON.generate(error.findings), 'secret raw backend error'

    transport = FakeTransport.new(tools: sloth_mcp_tools, oversized: true)
    client = SloRulesEngine::Sloth::Mcp::Client.new(config: runtime_config, transport: transport)
    error = assert_raises(SloRulesEngine::Sloth::Mcp::ContractError) { client.connect }
    assert_equal 'sloth_mcp_response_too_large', error.code
  end

  def test_runtime_requires_a_safe_endpoint_allowlist_version_range_and_bounds
    error = assert_raises(SloRulesEngine::Sloth::Mcp::ContractError) do
      runtime_config(endpoint: 'https://user:secret@mcp.example.test/mcp')
    end
    assert_equal 'invalid_sloth_mcp_endpoint', error.code

    error = assert_raises(SloRulesEngine::Sloth::Mcp::ContractError) do
      runtime_config(allowed_hosts: ['other.example.test'])
    end
    assert_equal 'sloth_mcp_endpoint_not_allowed', error.code

    error = assert_raises(SloRulesEngine::Sloth::Mcp::ContractError) do
      runtime_config(expected_version: 'v0.16.0')
    end
    assert_equal 'unsupported_sloth_mcp_version', error.code

    error = assert_raises(SloRulesEngine::Sloth::Mcp::ContractError) do
      runtime_config(max_pages: 0)
    end
    assert_equal 'invalid_sloth_mcp_bounds', error.code

    error = assert_raises(SloRulesEngine::Sloth::Mcp::ContractError) do
      runtime_config(from: '2026-08-05T00:00:00Z', to: '2026-08-01T00:00:00Z')
    end
    assert_equal 'invalid_sloth_mcp_range', error.code
  end

  private

  def runtime_config(**overrides)
    SloRulesEngine::Sloth::Mcp::RuntimeConfig.new(
      **{
        endpoint: 'https://mcp.example.test/mcp',
        allowed_hosts: ['mcp.example.test'],
        expected_version: MCP_VERSION,
        from: '2026-08-01T00:00:00Z',
        to: '2026-08-05T00:00:00Z'
      }.merge(overrides)
    )
  end
end
