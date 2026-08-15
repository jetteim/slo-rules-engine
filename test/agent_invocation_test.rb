# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'open3'
require 'rbconfig'
require 'stringio'
require 'tempfile'
load File.expand_path('../bin/rules-ctl', __dir__)

class AgentInvocationTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def test_inline_request_returns_versioned_deterministic_result_equivalent_to_human_cli
    human = invoke_human('providers', 'list')
    request = request_for('providers.list')

    first = invoke_agent('providers.list', "--json=#{JSON.generate(request)}")
    second = invoke_agent('providers.list', "--json=#{JSON.generate(request)}")

    assert_equal first, second
    assert_equal 'slo-rules-engine/agent-command-result/v1', first.fetch('schema_version')
    assert_equal 'AgentCommandResult', first.fetch('kind')
    assert_match(/\Areq-[0-9a-f]{24}\z/, first.fetch('request_id'))
    assert_equal 'providers.list', first.fetch('command_id')
    assert_equal 1, first.fetch('command_version')
    assert_equal 'succeeded', first.fetch('outcome')
    assert_equal 0, first.fetch('exit_status')
    assert_equal({ 'declared' => 'none', 'exercised' => 'none' }, first.fetch('side_effect'))
    assert_equal human, first.fetch('result')
    assert_empty first.fetch('findings')
    assert_empty first.fetch('artifacts')
    assert_equal false, first.dig('truncation', 'truncated')
  end

  def test_json_file_and_stdin_requests_use_the_same_contract
    file_request = request_for('integrations.list')
    Tempfile.create(['agent-request', '.json'], ROOT) do |file|
      file.write(JSON.generate(file_request))
      file.flush
      payload = invoke_agent('integrations.list', "--json-file=#{file.path}")
      assert_equal invoke_human('integrations', 'list'), payload.fetch('result')
    end

    stdin_request = JSON.generate(request_for('providers.list'))
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, 'bin/rules-ctl'),
      'agent', 'invoke', 'providers.list', '--stdin',
      stdin_data: stdin_request,
      chdir: ROOT
    )
    assert status.success?, stderr
    assert_empty stderr
    assert_equal invoke_human('providers', 'list'), JSON.parse(stdout).fetch('result')
  end

  def test_calculation_recommendation_uses_the_same_typed_application_command
    human = invoke_human(
      'recommend-calculation-basis',
      '--observations-per-second=0.5',
      '--failed-observations-to-alert=5.5'
    )
    request = mutable_request_for('recommend-calculation-basis')
    request[:arguments][:observations_per_second] = 0.5
    request[:arguments][:failed_observations_to_alert] = 5.5
    payload = invoke_agent(
      'recommend-calculation-basis',
      "--json=#{JSON.generate(request)}"
    )

    assert_equal human, payload.fetch('result')
    assert_equal 'none', payload.dig('side_effect', 'exercised')

    invalid = mutable_request_for('recommend-calculation-basis')
    invalid[:arguments][:observations_per_second] = -0.1
    error = invoke_agent_error(
      'recommend-calculation-basis',
      "--json=#{JSON.generate(invalid)}"
    )
    assert_equal 'invalid_agent_request', error.dig('error', 'code')
    assert_equal '$.arguments.observations_per_second', error.dig('error', 'details', 'errors', 0, 'path')
  end

  def test_invalid_sources_schema_and_target_fail_as_json_without_stderr
    error = invoke_agent_error(
      'providers.list',
      "--json=#{JSON.generate(request_for('providers.list'))}",
      '--json-file=missing.json'
    )
    assert_equal 'invalid_agent_request_source', error.dig('error', 'code')

    invalid = request_for('providers.list').merge(arguments: { unexpected: true })
    error = invoke_agent_error('providers.list', "--json=#{JSON.generate(invalid)}")
    assert_equal 'invalid_agent_request', error.dig('error', 'code')
    assert_match(/\Areq-[0-9a-f]{24}\z/, error.fetch('request_id'))
    assert_equal '$.arguments.unexpected', error.dig('error', 'details', 'errors', 0, 'path')

    mismatch = request_for('providers.list').merge(command_id: 'integrations.list')
    error = invoke_agent_error('providers.list', "--json=#{JSON.generate(mismatch)}")
    assert_equal 'invalid_agent_request', error.dig('error', 'code')

    unsupported = request_for('generate')
    error = invoke_agent_error('generate', "--json=#{JSON.generate(unsupported)}")
    assert_equal 'agent_command_not_executable', error.dig('error', 'code')
    assert_equal 'generate', error.fetch('command_id')

    error = invoke_agent_error('unknown.command', '--json={}')
    assert_equal 'unknown_agent_command', error.dig('error', 'code')

    error = invoke_agent_error('providers.list', '--json={not-json}')
    assert_equal 'malformed_agent_json', error.dig('error', 'code')
  end

  def test_json_file_must_resolve_inside_the_workspace
    Tempfile.create(['outside-agent-request', '.json']) do |file|
      file.write(JSON.generate(request_for('providers.list')))
      file.flush

      error = invoke_agent_error('providers.list', "--json-file=#{file.path}")
      assert_equal 'unsafe_agent_request_path', error.dig('error', 'code')
    end
  end

  def test_output_format_precedence_is_explicit_then_environment_then_json_default
    request_json = JSON.generate(request_for('providers.list'))
    previous = ENV['RULES_CTL_OUTPUT_FORMAT']
    ENV['RULES_CTL_OUTPUT_FORMAT'] = 'ndjson'

    payload = invoke_agent('providers.list', "--json=#{request_json}", '--format=json')
    assert_equal 'succeeded', payload.fetch('outcome')

    error = invoke_agent_error('providers.list', "--json=#{request_json}")
    assert_equal 'unsupported_agent_output_format', error.dig('error', 'code')
  ensure
    ENV['RULES_CTL_OUTPUT_FORMAT'] = previous
  end

  def test_application_commands_return_values_without_rendering_or_exiting
    stdout, stderr = capture_io do
      result = SloRulesEngine::Application::ListProviders.new.call(
        {},
        context: SloRulesEngine::Application::Context.new(
          provider_registry: SloRulesEngine.default_provider_registry,
          integration_registry: SloRulesEngine.default_integration_registry
        )
      )
      assert_equal 'none', result.side_effect
      assert_kind_of Array, result.value
    end

    assert_empty stdout
    assert_empty stderr
  end

  private

  def request_for(command_id)
    definition = SloRulesEngine::CLI::CommandRegistry.default.fetch(command_id)
    definition.agent.fetch(:request_example)
  end

  def mutable_request_for(command_id)
    JSON.parse(JSON.generate(request_for(command_id)), symbolize_names: true)
  end

  def invoke_human(*arguments)
    stdout, stderr = capture_io { RulesCtl.run(arguments) }
    assert_empty stderr
    JSON.parse(stdout)
  end

  def invoke_agent(command_id, *arguments)
    stdout, stderr = capture_io { RulesCtl.run(['agent', 'invoke', command_id, *arguments]) }
    assert_empty stderr
    JSON.parse(stdout)
  end

  def invoke_agent_error(command_id, *arguments)
    stdout, stderr = capture_io do
      error = assert_raises(SystemExit) do
        RulesCtl.run(['agent', 'invoke', command_id, *arguments])
      end
      assert_equal 1, error.status
    end
    assert_empty stderr
    payload = JSON.parse(stdout)
    assert_equal 'slo-rules-engine/agent-command-error/v1', payload.fetch('schema_version')
    assert_equal 'failed', payload.fetch('outcome')
    payload
  end
end
