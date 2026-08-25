# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'minitest/autorun'
require 'pathname'
require 'tmpdir'
load File.expand_path('../bin/rules-ctl', __dir__)

class AgentWriteCommandsTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  ExplodingDependency = Class.new do
    def method_missing(name, *)
      raise "unexpected I/O dependency call: #{name}"
    end

    def respond_to_missing?(_name, _include_private = false)
      true
    end
  end

  ProviderRegistry = Struct.new(:provider) do
    def fetch(_key)
      provider
    end
  end

  ProviderIdentity = Struct.new(:key)

  def setup
    @temporary_root = Dir.mktmpdir('agent-write-commands-', ROOT)
  end

  def teardown
    FileUtils.remove_entry(@temporary_root) if File.exist?(@temporary_root)
  end

  def test_generate_and_manifest_review_match_human_results_and_write_only_confined_artifacts
    output_dir = relative_path(File.join(@temporary_root, 'generated'))
    definition_file = 'examples/services/checkout.rb'

    human_generation, human_status = invoke_human(
      'generate', '--provider=prometheus_stack', "--output-dir=#{output_dir}", definition_file
    )
    agent_generation, agent_status = invoke_agent(
      'generate',
      provider: 'prometheus_stack',
      definition_files: [definition_file],
      output_dir: output_dir
    )

    assert_equal 0, human_status
    assert_equal human_status, agent_status
    assert_equal human_generation, agent_generation.fetch('result')
    assert_equal 'local_write', agent_generation.dig('side_effect', 'exercised')
    assert_equal %w[manifest_review_report provider_manifest],
                 agent_generation.fetch('artifacts').map { |artifact| artifact.fetch('kind') }.sort

    manifest_file = File.join(output_dir, 'checkout-api', 'prometheus_stack', 'manifest.json')
    review_file = relative_path(File.join(@temporary_root, 'review.json'))
    human_review, human_status = invoke_human(
      'manifest-review', '--provider=prometheus_stack', "--manifest=#{manifest_file}", "--output=#{review_file}"
    )
    agent_review, agent_status = invoke_agent(
      'manifest-review',
      provider: 'prometheus_stack',
      manifest_files: [manifest_file],
      output_file: review_file
    )

    assert_equal 1, human_status
    assert_equal human_status, agent_status
    assert_equal human_review, agent_review.fetch('result')
    assert_equal 'failed', agent_review.fetch('outcome')
    assert File.file?(File.join(ROOT, review_file))
  end

  def test_validate_only_is_zero_io_for_both_local_write_commands
    context = SloRulesEngine::Application::Context.new(
      provider_registry: ProviderRegistry.new(ProviderIdentity.new('prometheus_stack')),
      integration_registry: ExplodingDependency.new,
      input_policy: SloRulesEngine::Application::InputSafety::PathPolicy.agent(workspace_root: @temporary_root)
    )
    generation_output = 'new/generated'
    review_output = 'new/review.json'

    generation = SloRulesEngine::Application::GenerateProviderManifests.new(
      loader: ExplodingDependency.new,
      writer: ExplodingDependency.new
    ).call(
      {
        'provider' => 'prometheus_stack',
        'definition_files' => ['missing/service.rb'],
        'output_dir' => generation_output,
        'validate_only' => true
      },
      context: context
    )
    review = SloRulesEngine::Application::ReviewProviderManifests.new(
      definition_loader: ExplodingDependency.new,
      manifest_loader: ExplodingDependency.new,
      writer: ExplodingDependency.new
    ).call(
      {
        'provider' => 'prometheus_stack',
        'manifest_files' => ['missing/manifest.json'],
        'output_file' => review_output,
        'validate_only' => true
      },
      context: context
    )

    [generation, review].each do |result|
      assert_equal 'none', result.side_effect
      assert_equal true, result.value.fetch(:valid)
      assert_equal false, result.value.dig(:io, :local_reads)
      assert_equal false, result.value.dig(:io, :local_writes)
      assert_equal false, result.value.dig(:io, :provider_calls)
      assert_equal false, result.value.dig(:io, :credential_loading)
    end
    refute File.exist?(File.join(@temporary_root, 'new'))
  end

  def test_agent_validate_only_returns_zero_io_evidence_without_opening_missing_sources
    generation, generation_status = invoke_agent(
      'generate',
      provider: 'prometheus_stack',
      definition_files: [relative_path(File.join(@temporary_root, 'missing.rb'))],
      output_dir: relative_path(File.join(@temporary_root, 'future-output')),
      validate_only: true
    )
    review, review_status = invoke_agent(
      'manifest-review',
      provider: 'prometheus_stack',
      manifest_files: [relative_path(File.join(@temporary_root, 'missing.json'))],
      output_file: relative_path(File.join(@temporary_root, 'future-review.json')),
      validate_only: true
    )

    assert_equal 0, generation_status
    assert_equal 0, review_status
    [generation, review].each do |payload|
      assert_equal({ 'declared' => 'local_write', 'exercised' => 'none' }, payload.fetch('side_effect'))
      assert_equal 'validate_only', payload.dig('result', 'mode')
      assert_equal false, payload.dig('result', 'io', 'local_reads')
      assert_equal false, payload.dig('result', 'io', 'local_writes')
      assert_empty payload.fetch('artifacts')
    end
    refute File.exist?(File.join(@temporary_root, 'future-output'))
    refute File.exist?(File.join(@temporary_root, 'future-review.json'))
  end

  def test_agent_output_paths_reject_traversal_absolute_preencoding_controls_and_symlink_escape
    definition_file = 'examples/services/checkout.rb'
    ['../outside', '/tmp/outside', '%2e%2e/outside'].each do |path|
      error, status = invoke_agent(
        'generate',
        provider: 'prometheus_stack',
        definition_files: [definition_file],
        output_dir: path
      )
      assert_equal 1, status
      assert_equal 'unsafe_agent_output_path', error.dig('error', 'code'), path
    end

    error, status = invoke_agent(
      'manifest-review',
      provider: 'prometheus_stack',
      manifest_files: [relative_path(File.join(@temporary_root, 'missing.json'))],
      output_file: "bad\nreview.json"
    )
    assert_equal 1, status
    assert_equal 'invalid_agent_request', error.dig('error', 'code')

    Dir.mktmpdir('agent-write-outside-') do |outside|
      link = File.join(@temporary_root, 'escape')
      File.symlink(outside, link)
      error, status = invoke_agent(
        'generate',
        provider: 'prometheus_stack',
        definition_files: [definition_file],
        output_dir: relative_path(File.join(link, 'generated'))
      )
      assert_equal 1, status
      assert_equal 'unsafe_agent_output_path', error.dig('error', 'code')
      assert_equal 'symlink_escape', error.dig('error', 'details', 'reason')
    end
  end

  def test_unsafe_output_is_rejected_before_a_missing_input_is_opened
    error, status = invoke_agent(
      'generate',
      provider: 'prometheus_stack',
      definition_files: [relative_path(File.join(@temporary_root, 'missing.rb'))],
      output_dir: '../outside'
    )

    assert_equal 1, status
    assert_equal 'unsafe_agent_output_path', error.dig('error', 'code')
    assert_equal 'output_dir', error.dig('error', 'details', 'field')
  end

  def test_generated_child_paths_cannot_escape_the_confined_output_root
    writer = SloRulesEngine::Application::LocalArtifactWriter.new
    policy = SloRulesEngine::Application::InputSafety::PathPolicy.agent(workspace_root: @temporary_root)
    output_root = policy.resolve_write_root('generated', field: 'output_dir')
    manifest = { service: '../outside', provider: 'prometheus_stack' }

    error = assert_raises(SloRulesEngine::Application::InputSafety::Error) do
      writer.write_provider_manifests(
        output_root,
        [manifest],
        provider: ProviderIdentity.new('prometheus_stack'),
        handoff_dir: nil,
        path_policy: policy,
        report_path_root: 'generated'
      )
    end

    assert_equal 'unsafe_agent_output_path', error.code
    assert_equal 'generated_artifacts', error.details.fetch(:field)
    assert_equal 'unsafe_generated_segment', error.details.fetch(:reason)
    refute File.exist?(File.join(@temporary_root, 'outside'))
  end

  private

  def relative_path(path)
    Pathname.new(path).relative_path_from(Pathname.new(ROOT)).to_s
  end

  def invoke_human(*arguments)
    invoke_rules_ctl(arguments)
  end

  def invoke_agent(command_id, **arguments)
    request = SloRulesEngine::CLI::CommandRegistry.default.fetch(command_id).agent.fetch(:request_example)
    request = JSON.parse(JSON.generate(request), symbolize_names: true)
    request[:arguments] = arguments
    invoke_rules_ctl(['agent', 'invoke', command_id, "--json=#{JSON.generate(request)}"])
  end

  def invoke_rules_ctl(arguments)
    status = 0
    stdout, stderr = capture_io do
      RulesCtl.run(arguments.dup)
    rescue SystemExit => error
      status = error.status
    end
    assert_empty stderr
    [JSON.parse(stdout), status]
  end
end
