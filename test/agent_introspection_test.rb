# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'open3'
load File.expand_path('../bin/rules-ctl', __dir__)

class AgentIntrospectionTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def test_catalog_is_offline_bounded_and_continuable
    first = invoke('agent', 'catalog', '--format=json', '--limit=2')

    assert_equal 'slo-rules-engine/agent-command-catalog/v1', first.fetch('schema_version')
    assert_equal 'AgentCommandCatalog', first.fetch('kind')
    assert_equal 'slo-rules-engine/cli-command-registry/v1', first.fetch('registry_schema_version')
    assert_equal 40, first.fetch('total_commands')
    assert_equal 2, first.dig('page', 'returned')
    assert_equal 2, first.fetch('commands').length
    assert_equal true, first.dig('page', 'truncated')
    refute_nil first.dig('page', 'next_cursor')
    first.fetch('commands').each do |entry|
      assert_equal %w[
        agent_cli_json human_cli id io mcp output safety_gates schemas side_effect version
      ], entry.keys.sort
      assert_equal entry.fetch('id'), entry.dig('agent_cli_json', 'command_id')
    end

    second = invoke(
      'agent', 'catalog', '--format=json', '--limit=2',
      "--cursor=#{first.dig('page', 'next_cursor')}"
    )
    assert_empty first.fetch('commands').map { |entry| entry.fetch('id') } &
                 second.fetch('commands').map { |entry| entry.fetch('id') }
    refute_includes JSON.generate(first), 'generated_at'
  end

  def test_describe_resolves_the_complete_strict_request_contract
    description = invoke('agent', 'describe', 'sloth-mcp.compare', '--format=json')

    assert_equal 'slo-rules-engine/agent-command-description/v1', description.fetch('schema_version')
    assert_equal 'AgentCommandDescription', description.fetch('kind')
    command = description.fetch('command')
    assert_equal 'sloth-mcp.compare', command.fetch('id')
    assert_equal 'provider_read', command.fetch('side_effect')
    assert_equal ['sloth_mcp_read_only_tools'], command.dig('io', 'provider_reads')
    assert_empty command.dig('io', 'provider_writes')
    assert_empty command.dig('io', 'credentials')
    request = command.fetch('request_schema')
    assert_equal false, request.fetch('additionalProperties')
    assert_equal %w[arguments command_id command_version schema_version], request.fetch('required').sort
    arguments = request.dig('properties', 'arguments')
    assert_equal false, arguments.fetch('additionalProperties')
    assert_equal 'uri', arguments.dig('properties', 'endpoint', 'format')
    assert_equal 'array', arguments.dig('properties', 'allowed_hosts', 'type')
    assert_includes arguments.fetch('required'), 'manifest_file'
    assert_includes arguments.fetch('required'), 'output_file'
    assert_equal 'sloth-mcp.compare', request.dig('properties', 'command_id', 'const')
  end

  def test_every_registered_agent_target_has_a_resolved_schema_matching_its_example
    registry = SloRulesEngine::CLI::CommandRegistry.default

    assert_equal 40, registry.definitions.length
    registry.definitions.each do |definition|
      schema = definition.request_schema
      arguments_schema = schema.dig(:properties, :arguments)
      example = definition.agent.dig(:request_example, :arguments)
      assert_equal false, schema.fetch(:additionalProperties), definition.id
      assert_equal false, arguments_schema.fetch(:additionalProperties), definition.id
      assert_empty example.keys.map(&:to_sym) - arguments_schema.fetch(:properties).keys,
                   definition.id
      assert_empty arguments_schema.fetch(:required) - example.keys.map(&:to_s), definition.id
      assert_equal definition.id, schema.dig(:properties, :command_id, :const)
      assert_equal definition.version, schema.dig(:properties, :command_version, :const)
    end
  end

  def test_unknown_command_and_cursor_return_machine_errors_without_stderr
    stdout, stderr = capture_io do
      error = assert_raises(SystemExit) do
        RulesCtl.run(%w[agent describe unknown.command --format=json])
      end
      assert_equal 1, error.status
    end
    assert_empty stderr
    payload = JSON.parse(stdout)
    assert_equal 'slo-rules-engine/agent-command-error/v1', payload.fetch('schema_version')
    assert_equal 'unknown_agent_command', payload.dig('error', 'code')

    stdout, stderr = capture_io do
      error = assert_raises(SystemExit) do
        RulesCtl.run(%w[agent catalog --cursor=unknown.command --format=json])
      end
      assert_equal 1, error.status
    end
    assert_empty stderr
    assert_equal 'invalid_agent_catalog_cursor', JSON.parse(stdout).dig('error', 'code')
  end

  def test_binary_exposes_introspection_without_source_or_backend_inputs
    stdout, stderr, status = Open3.capture3(
      'ruby', File.join(ROOT, 'bin', 'rules-ctl'),
      'agent', 'describe', 'validate', '--format=json'
    )

    assert status.success?, stderr
    assert_empty stderr
    payload = JSON.parse(stdout)
    assert_equal 'validate', payload.dig('command', 'id')
    assert_equal ['definition_files'],
                 payload.dig('command', 'request_schema', 'properties', 'arguments', 'required')
  end

  private

  def invoke(*arguments)
    stdout, stderr = capture_io { RulesCtl.run(arguments) }
    assert_empty stderr
    JSON.parse(stdout)
  end
end
