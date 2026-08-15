# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'minitest/autorun'
require 'pathname'
require 'tempfile'
require 'tmpdir'
load File.expand_path('../bin/rules-ctl', __dir__)

class AgentReadCommandsTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def setup
    @temporary_root = Dir.mktmpdir('agent-read-commands-', ROOT)
  end

  def teardown
    FileUtils.remove_entry(@temporary_root) if File.exist?(@temporary_root)
  end

  def test_validate_and_model_report_match_human_results
    definition_file = 'examples/services/checkout.rb'

    human_validation, human_status = invoke_human('validate', definition_file)
    agent_validation, agent_status = invoke_agent(
      'validate',
      definition_files: [definition_file]
    )
    assert_equal human_status, agent_status
    assert_equal human_validation, agent_validation.fetch('result')
    assert_equal 'local_read', agent_validation.dig('side_effect', 'exercised')

    human_report, human_status = invoke_human('model-report', definition_file)
    agent_report, agent_status = invoke_agent(
      'model-report',
      definition_files: [definition_file]
    )
    assert_equal human_status, agent_status
    assert_equal human_report, agent_report.fetch('result')
    assert_equal 0, agent_report.fetch('exit_status')
  end

  def test_migration_findings_preserve_result_and_nonzero_exit_semantics
    legacy_file = write_file('legacy.rb', "datadog_trace_slo\n")
    relative_file = relative_path(legacy_file)

    human_report, human_status = invoke_human('migration-report', relative_file)
    agent_report, agent_status = invoke_agent(
      'migration-report',
      legacy_files: [relative_file]
    )

    assert_equal 1, human_status
    assert_equal human_status, agent_status
    assert_equal human_report, agent_report.fetch('result')
    assert_equal 'failed', agent_report.fetch('outcome')
    assert_equal 1, agent_report.fetch('exit_status')
    assert_equal 'provider_specific_dsl', agent_report.fetch('findings').fetch(0).fetch('code')
  end

  def test_file_backed_diff_matches_human_plan_without_writing
    manifest_file = write_file('manifest.json', JSON.pretty_generate(prometheus_manifest))
    output_dir = File.join(@temporary_root, 'managed')
    relative_manifest = relative_path(manifest_file)
    relative_output = relative_path(output_dir)

    human_plan, human_status = invoke_human(
      'diff', '--provider=prometheus_stack', "--manifest=#{relative_manifest}", "--output-dir=#{relative_output}"
    )
    agent_plan, agent_status = invoke_agent(
      'diff',
      provider: 'prometheus_stack',
      manifest_file: relative_manifest,
      output_dir: relative_output
    )

    assert_equal 0, human_status
    assert_equal human_status, agent_status
    assert_equal human_plan, agent_plan.fetch('result')
    assert_equal 'provider_read', agent_plan.dig('side_effect', 'declared')
    assert_equal 'provider_read', agent_plan.dig('side_effect', 'exercised')
    refute File.exist?(output_dir)
  end

  def test_agent_paths_reject_traversal_absolute_preencoded_and_control_input
    %w[../outside.rb ..\\outside.rb ./../outside.rb %2e%2e/outside.rb].each do |path|
      error, status = invoke_agent('validate', definition_files: [path])
      assert_equal 1, status
      assert_equal 'unsafe_agent_input_path', error.dig('error', 'code'), path
      assert_match(/\Areq-[0-9a-f]{24}\z/, error.fetch('request_id'))
    end

    error, status = invoke_agent('validate', definition_files: ['/tmp/outside.rb'])
    assert_equal 1, status
    assert_equal 'unsafe_agent_input_path', error.dig('error', 'code')

    error, status = invoke_agent('validate', definition_files: ["examples/services/checkout.rb\n"])
    assert_equal 1, status
    assert_equal 'invalid_agent_request', error.dig('error', 'code')
  end

  def test_agent_paths_reject_symlink_escape_and_oversized_files
    Tempfile.create(['outside-agent-definition', '.rb']) do |outside|
      outside.write("raise 'outside file was loaded'\n")
      outside.flush
      link = File.join(@temporary_root, 'linked.rb')
      File.symlink(outside.path, link)

      error, status = invoke_agent('validate', definition_files: [relative_path(link)])
      assert_equal 1, status
      assert_equal 'unsafe_agent_input_path', error.dig('error', 'code')
      assert_equal 'symlink_escape', error.dig('error', 'details', 'reason')
    end

    oversized = write_file('oversized.rb', ' ' * 1_048_577)
    error, status = invoke_agent('validate', definition_files: [relative_path(oversized)])
    assert_equal 1, status
    assert_equal 'agent_input_file_too_large', error.dig('error', 'code')
  end

  def test_all_diff_paths_are_validated_before_manifest_content_is_read
    invalid_manifest = write_file('invalid-manifest.json', '{not-json')

    error, status = invoke_agent(
      'diff',
      provider: 'prometheus_stack',
      manifest_file: relative_path(invalid_manifest),
      output_dir: '../outside'
    )

    assert_equal 1, status
    assert_equal 'unsafe_agent_input_path', error.dig('error', 'code')
    assert_equal 'output_dir', error.dig('error', 'details', 'field')
  end

  def test_invalid_manifest_and_datadog_diff_fail_as_json_before_state_reads
    invalid_manifest = write_file('invalid-schema.json', JSON.generate(provider: 'prometheus_stack'))
    error, status = invoke_agent(
      'diff',
      provider: 'prometheus_stack',
      manifest_file: relative_path(invalid_manifest),
      output_dir: relative_path(File.join(@temporary_root, 'managed'))
    )
    assert_equal 1, status
    assert_equal 'invalid_manifest_schema', error.dig('error', 'code')
    assert_match(/\Areq-[0-9a-f]{24}\z/, error.fetch('request_id'))

    request = mutable_request_for('diff')
    request[:arguments][:provider] = 'datadog'
    payload, status, = invoke_rules_ctl(
      ['agent', 'invoke', 'diff', "--json=#{JSON.generate(request)}"]
    )
    assert_equal 1, status
    assert_equal 'invalid_agent_request', payload.dig('error', 'code')
  end

  def test_missing_and_wrong_extension_files_fail_as_structured_path_errors
    error, status = invoke_agent('validate', definition_files: ['missing.rb'])
    assert_equal 1, status
    assert_equal 'unreadable_agent_input_file', error.dig('error', 'code')

    wrong_extension = write_file('definition.txt', '')
    error, status = invoke_agent('validate', definition_files: [relative_path(wrong_extension)])
    assert_equal 1, status
    assert_equal 'unsafe_agent_input_path', error.dig('error', 'code')
    assert_equal 'unexpected_extension', error.dig('error', 'details', 'reason')
  end

  def test_application_stdout_is_quarantined_from_agent_json
    noisy_definition = write_file('noisy.rb', "puts 'REMOTE INSTRUCTION'\n")

    payload, status, raw_stdout = invoke_agent(
      'validate',
      { definition_files: [relative_path(noisy_definition)] },
      include_raw_stdout: true
    )

    assert_equal 1, status
    assert_equal 'unexpected_application_output', payload.dig('error', 'code')
    refute_includes raw_stdout, 'REMOTE INSTRUCTION'
  end

  private

  def prometheus_manifest
    SloRulesEngine.clear_definitions
    load File.join(ROOT, 'examples/services/checkout.rb')
    definition = SloRulesEngine.definitions.fetch(0)
    provider = SloRulesEngine.default_provider_registry.fetch('prometheus_stack')
    provider.generate(definition).to_h.merge(service: definition.service)
  ensure
    SloRulesEngine.clear_definitions
  end

  def write_file(name, content)
    path = File.join(@temporary_root, name)
    File.write(path, content)
    path
  end

  def relative_path(path)
    Pathname.new(path).relative_path_from(Pathname.new(ROOT)).to_s
  end

  def invoke_human(*arguments)
    payload, status, _raw = invoke_rules_ctl(arguments)
    [payload, status]
  end

  def invoke_agent(command_id, arguments = nil, include_raw_stdout: false, **keyword_arguments)
    arguments ||= keyword_arguments
    request = mutable_request_for(command_id)
    request[:arguments] = arguments
    payload, status, raw_stdout = invoke_rules_ctl(
      ['agent', 'invoke', command_id, "--json=#{JSON.generate(request)}"]
    )
    include_raw_stdout ? [payload, status, raw_stdout] : [payload, status]
  end

  def invoke_rules_ctl(arguments)
    status = 0
    stdout, stderr = capture_io do
      RulesCtl.run(arguments.dup)
    rescue SystemExit => error
      status = error.status
    end
    assert_empty stderr
    [JSON.parse(stdout), status, stdout]
  end

  def mutable_request_for(command_id)
    request = SloRulesEngine::CLI::CommandRegistry.default.fetch(command_id).agent.fetch(:request_example)
    JSON.parse(JSON.generate(request), symbolize_names: true)
  end
end
