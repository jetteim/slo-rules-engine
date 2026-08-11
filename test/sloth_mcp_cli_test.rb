# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'tmpdir'
require_relative 'support/release_bundle_fixtures'
require_relative 'support/sloth_mcp_fixtures'
load File.expand_path('../bin/rules-ctl', __dir__)

class SlothMcpCliTest < Minitest::Test
  include ReleaseBundleFixtures
  include SlothMcpFixtures

  FROM = '2026-08-01T00:00:00Z'
  TO = '2026-08-05T00:00:00Z'

  def test_compare_writes_the_exact_stdout_report_and_succeeds_when_state_matches
    with_sources do |sources|
      client = FakeSlothMcpClient.new(tools: sloth_mcp_tools, outputs: sloth_mcp_outputs)
      comparator = comparator(client)
      output = File.join(sources.fetch(:dir), 'comparison.json')

      stdout, _stderr = capture_io do
        stub_comparator(comparator) do
          RulesCtl.run(['sloth-mcp', 'compare', *arguments(sources, output)])
        end
      end

      payload = JSON.parse(stdout)
      assert_equal 'matched', payload.fetch('status')
      assert_equal payload, JSON.parse(File.read(output))
      assert_equal SloRulesEngine::Sloth::Mcp::TOOL_CONTRACTS.keys.sort,
                   payload.fetch('runtime').fetch('tools')
    end
  end

  def test_compare_persists_drift_and_exits_one
    with_sources do |sources|
      outputs = sloth_mcp_outputs(objective: 99.0)
      client = FakeSlothMcpClient.new(tools: sloth_mcp_tools, outputs: outputs)
      output = File.join(sources.fetch(:dir), 'comparison.json')

      stdout, _stderr = capture_io do
        error = assert_raises(SystemExit) do
          stub_comparator(comparator(client)) do
            RulesCtl.run(['sloth-mcp', 'compare', *arguments(sources, output)])
          end
        end
        assert_equal 1, error.status
      end

      payload = JSON.parse(stdout)
      assert_equal 'drift', payload.fetch('status')
      assert_equal payload, JSON.parse(File.read(output))
    end
  end

  def test_compare_renders_sanitized_contract_errors_without_writing_output
    with_sources do |sources|
      output = File.join(sources.fetch(:dir), 'comparison.json')
      error = SloRulesEngine::Sloth::Mcp::ContractError.new(
        'sloth_mcp_transport_failed',
        'Sloth MCP request failed.',
        findings: [SloRulesEngine::Sloth::Mcp::Support.finding(
          'sloth_mcp_transport_failed',
          'Sloth MCP request failed.',
          error_class: 'SocketError'
        )]
      )
      comparator = Object.new
      comparator.define_singleton_method(:compare) { |**_arguments| raise error }

      stdout, _stderr = capture_io do
        exit_error = assert_raises(SystemExit) do
          stub_comparator(comparator) do
            RulesCtl.run(['sloth-mcp', 'compare', *arguments(sources, output)])
          end
        end
        assert_equal 1, exit_error.status
      end

      payload = JSON.parse(stdout)
      assert_equal false, payload.fetch('valid')
      assert_equal 'sloth_mcp_transport_failed', payload.fetch('error').fetch('code')
      refute_includes stdout, 'mcp.example.test'
      refute File.exist?(output)
    end
  end

  private

  def with_sources
    Dir.mktmpdir do |dir|
      fixture = write_release_bundle_fixture(dir, provider: 'sloth')
      evidence = write_sloth_downstream_evidence_fixture(dir, fixture.fetch(:manifest))
      yield(dir: dir, manifest: fixture.fetch(:manifest), evidence: evidence.fetch(:evidence))
    end
  end

  def comparator(client)
    SloRulesEngine::Sloth::Mcp::Comparison.new(
      client_factory: ->(**_options) { client },
      clock: -> { Time.iso8601(TO) }
    )
  end

  def arguments(sources, output)
    [
      "--manifest=#{sources.fetch(:manifest)}",
      "--evidence=#{sources.fetch(:evidence)}",
      '--endpoint=https://mcp.example.test/mcp',
      '--allow-host=mcp.example.test',
      "--expected-version=#{MCP_VERSION}",
      "--from=#{FROM}",
      "--to=#{TO}",
      "--output=#{output}"
    ]
  end

  def stub_comparator(comparator)
    original = RulesCtl.method(:sloth_mcp_comparison)
    RulesCtl.define_singleton_method(:sloth_mcp_comparison) { comparator }
    yield
  ensure
    RulesCtl.define_singleton_method(:sloth_mcp_comparison) { original.call }
  end
end
