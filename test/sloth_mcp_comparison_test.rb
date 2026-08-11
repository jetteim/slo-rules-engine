# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative 'support/release_bundle_fixtures'
require_relative 'support/sloth_mcp_fixtures'

class SlothMcpComparisonTest < Minitest::Test
  include ReleaseBundleFixtures
  include SlothMcpFixtures

  FROM = '2026-08-01T00:00:00Z'
  TO = '2026-08-05T00:00:00Z'

  def test_compares_every_official_read_only_tool_with_exact_reviewed_identity
    with_sources do |sources|
      client = FakeSlothMcpClient.new(
        tools: sloth_mcp_tools,
        outputs: paginated_outputs
      )

      report = comparison(client).compare(**comparison_arguments(sources))

      assert_equal 'slo-rules-engine/sloth-mcp-comparison/v1', report.fetch(:schema_version)
      assert_equal 'matched', report.fetch(:status)
      assert_equal 'sloth', report.fetch(:provider)
      assert_equal MCP_SERVICE, report.fetch(:service)
      assert_match(/\Asloth-mcp-comparison-[0-9a-f]{64}\z/, report.fetch(:comparison_id))
      assert_equal MCP_PROTOCOL_VERSION, report.dig(:runtime, :protocol_version)
      assert_equal({ name: 'sloth', version: MCP_VERSION }, report.dig(:runtime, :server))
      assert_equal sloth_mcp_tools.map { |tool| tool.fetch('name') }.sort,
                   report.dig(:runtime, :tools)
      assert_equal 1, report.dig(:summary, :expected_slos)
      assert_equal 1, report.dig(:summary, :matched_slos)
      assert_equal 0, report.dig(:summary, :drifted_slos)
      result = report.fetch(:slos).fetch(0)
      assert_equal MCP_SLOTH_ID, result.dig(:identity, :sloth_id)
      assert_equal MCP_SLO_ID, result.dig(:provider, :slo_id)
      assert_equal [100.0, 95.0, nil, 90.0],
                   result.dig(:provider, :burned_budget_range, :real_values)
      assert_equal [99.99, 99.98, nil, 99.97],
                   result.dig(:provider, :availability_range, :values)
      assert_equal %w[
        context
        list_services
        list_services
        list_slos
        list_slos
        get_slo
        get_slo_burned_budget_range
        get_slo_sli_availability_range
      ], client.calls.map(&:first)
      serialized = JSON.generate(report)
      refute_includes serialized, 'mcp.example.test'
      refute_includes serialized, 'provider-controlled text'
      refute_includes serialized, 'page_alert_name'
    end
  end

  def test_emits_a_drift_report_for_objective_period_budget_and_burn_mismatch
    with_sources do |sources|
      outputs = sloth_mcp_outputs(objective: 99.0, period: '168h0m0s')
      detailed = sloth_mcp_slo(objective: 98.0, period: '24h0m0s')
      detailed['burning_budget_percent'] = 21.0
      detailed['burned_budget_window_percent'] = 12.0
      outputs['get_slo'] = { 'slo' => detailed }
      outputs.fetch('get_slo_burned_budget_range')['current_burned_value_percent'] = 80.0
      client = FakeSlothMcpClient.new(tools: sloth_mcp_tools, outputs: outputs)

      report = comparison(client).compare(**comparison_arguments(sources))

      assert_equal 'drift', report.fetch(:status)
      assert_equal 1, report.dig(:summary, :drifted_slos)
      codes = report.fetch(:findings).map { |finding| finding.fetch(:code) }
      assert_includes codes, 'sloth_mcp_objective_mismatch'
      assert_includes codes, 'sloth_mcp_period_mismatch'
      assert_includes codes, 'sloth_mcp_detail_mismatch'
      assert_includes codes, 'sloth_mcp_budget_mismatch'
    end
  end

  def test_rejects_unknown_or_changed_tools_before_any_domain_call
    with_sources do |sources|
      tools = sloth_mcp_tools + [tool_contract('mutate_slo', {}, { ok: 'boolean' })]
      client = FakeSlothMcpClient.new(tools: tools, outputs: sloth_mcp_outputs)

      error = assert_raises(SloRulesEngine::Sloth::Mcp::ContractError) do
        comparison(client).compare(**comparison_arguments(sources))
      end

      assert_equal 'invalid_sloth_mcp_contract', error.code
      assert_includes error.findings.map { |finding| finding.fetch(:code) },
                      'unexpected_sloth_mcp_tool'
      assert_empty client.calls

      changed = sloth_mcp_tools
      changed.fetch(2).fetch('outputSchema').fetch('properties').delete('pagination')
      client = FakeSlothMcpClient.new(tools: changed, outputs: sloth_mcp_outputs)
      error = assert_raises(SloRulesEngine::Sloth::Mcp::ContractError) do
        comparison(client).compare(**comparison_arguments(sources))
      end
      assert_includes error.findings.map { |finding| finding.fetch(:code) },
                      'sloth_mcp_tool_schema_mismatch'
      assert_empty client.calls
    end
  end

  def test_rejects_stale_reviewed_evidence_before_client_construction
    with_sources do |sources|
      generated = YAML.safe_load(File.read(sources.fetch(:generated)), aliases: false)
      generated.fetch('groups').fetch(0).fetch('rules').fetch(0)['expr'] = 'vector(0)'
      File.write(sources.fetch(:generated), YAML.dump(generated))
      clients = 0

      error = assert_raises(SloRulesEngine::Sloth::Mcp::ContractError) do
        SloRulesEngine::Sloth::Mcp::Comparison.new(
          client_factory: lambda do |**_options|
            clients += 1
            raise 'client must not be constructed'
          end
        ).compare(**comparison_arguments(sources))
      end

      assert_equal 'invalid_sloth_mcp_evidence', error.code
      assert_includes error.findings.map { |finding| finding.fetch(:code) },
                      'stale_generated_rules'
      assert_equal 0, clients
    end
  end

  def test_rejects_version_identity_and_pagination_gaps
    with_sources do |sources|
      client = FakeSlothMcpClient.new(
        tools: sloth_mcp_tools,
        outputs: sloth_mcp_outputs,
        version: 'v0.16.0'
      )
      error = assert_raises(SloRulesEngine::Sloth::Mcp::ContractError) do
        comparison(client).compare(**comparison_arguments(sources))
      end
      assert_includes error.findings.map { |finding| finding.fetch(:code) },
                      'unsupported_sloth_mcp_version'

      outputs = sloth_mcp_outputs
      outputs['list_slos'] = lambda do |arguments|
        {
          'slos' => arguments['cursor'].to_s.empty? ? [] : [sloth_mcp_slo],
          'pagination' => {
            'next_cursor' => 'same-cursor',
            'has_next' => true,
            'has_previous' => false
          }
        }
      end
      client = FakeSlothMcpClient.new(tools: sloth_mcp_tools, outputs: outputs)
      error = assert_raises(SloRulesEngine::Sloth::Mcp::ContractError) do
        comparison(client).compare(**comparison_arguments(sources).merge(max_pages: 2))
      end
      assert_includes error.findings.map { |finding| finding.fetch(:code) },
                      'sloth_mcp_pagination_cycle'
    end
  end

  def test_accepts_the_official_zero_step_for_single_point_series
    with_sources do |sources|
      outputs = sloth_mcp_outputs
      budget = outputs.fetch('get_slo_burned_budget_range')
      budget['step'] = '0s'
      budget['real_series'] = '95'
      budget['perfect_series'] = '100'
      availability = outputs.fetch('get_slo_sli_availability_range')
      availability['step'] = '0s'
      availability['availability_series'] = '99.99'
      client = FakeSlothMcpClient.new(tools: sloth_mcp_tools, outputs: outputs)

      report = comparison(client).compare(**comparison_arguments(sources))

      assert_equal 0.0, report.dig(:slos, 0, :provider, :burned_budget_range, :step_seconds)
      assert_equal 0.0, report.dig(:slos, 0, :provider, :availability_range, :step_seconds)
    end
  end

  private

  def with_sources
    Dir.mktmpdir do |dir|
      fixture = write_release_bundle_fixture(dir, provider: 'sloth')
      evidence = write_sloth_downstream_evidence_fixture(dir, fixture.fetch(:manifest))
      yield(
        manifest: fixture.fetch(:manifest),
        evidence: evidence.fetch(:evidence),
        generated: evidence.fetch(:generated)
      )
    end
  end

  def comparison(client)
    SloRulesEngine::Sloth::Mcp::Comparison.new(
      client_factory: ->(**_options) { client },
      clock: -> { Time.iso8601(TO) }
    )
  end

  def comparison_arguments(sources)
    {
      manifest_path: sources.fetch(:manifest),
      evidence_path: sources.fetch(:evidence),
      endpoint: 'https://mcp.example.test/mcp',
      allowed_hosts: ['mcp.example.test'],
      expected_version: MCP_VERSION,
      from: FROM,
      to: TO,
      page_size: 1,
      max_pages: 4,
      max_series_points: 10
    }
  end

  def paginated_outputs
    outputs = sloth_mcp_outputs
    outputs['list_services'] = lambda do |arguments|
      if arguments['cursor'].to_s.empty?
        {
          'services' => [],
          'pagination' => { 'next_cursor' => 'services-2', 'has_next' => true }
        }
      else
        sloth_mcp_outputs.fetch('list_services')
      end
    end
    outputs['list_slos'] = lambda do |arguments|
      if arguments['cursor'].to_s.empty?
        {
          'slos' => [],
          'pagination' => { 'next_cursor' => 'slos-2', 'has_next' => true }
        }
      else
        sloth_mcp_outputs.fetch('list_slos')
      end
    end
    outputs
  end
end
