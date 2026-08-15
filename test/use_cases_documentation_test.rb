# frozen_string_literal: true

require 'minitest/autorun'

class UseCasesDocumentationTest < Minitest::Test
  USE_CASES_PATH = File.expand_path('../docs/use-cases.md', __dir__)
  README_PATH = File.expand_path('../README.md', __dir__)

  def test_every_use_case_names_expected_outputs_and_intent_boundary
    sections.each do |heading, body|
      assert_includes body, '**What to expect:**', "#{heading} must state concrete expected outputs"
      assert_match(
        /\*\*(Intent preserved|Safety boundary):\*\*/,
        body,
        "#{heading} must state the intent or safety boundary"
      )
    end
  end

  def test_output_map_covers_every_provider_and_operation_journals
    document = File.read(USE_CASES_PATH)

    assert_includes document, '| `datadog` |'
    assert_includes document, '| `prometheus_stack` |'
    assert_includes document, '| `sloth` |'
    assert_includes document, '| Operation journal |'
  end

  def test_usage_covers_durable_provider_execution_results
    document = File.read(USE_CASES_PATH)
    readme = File.read(README_PATH)

    assert_operator document.scan('--journal-dir').length, :>=, 3
    assert_includes document, 'ProviderStateResult'
    assert_includes document, 'partial_failure'
    assert_includes readme, '--journal-dir=./work/journals'
    assert_includes readme, 'ProviderStateResult'
    assert_includes document, 'expected presence/content fingerprint'
    assert_includes document, 'engine_owned_status: succeeded'
    assert_includes readme, 'expected and actual state'
    assert_includes document, 'backend_resource_present_after_delete'
    assert_includes document, 'Raw responses and raw backend error messages are not persisted'
    assert_includes readme, 'canonical payload or confirmed delete absence'
    assert_includes document, 'paginated custom-dashboard catalog'
    assert_includes readme, 'manual dashboard-list membership is not required'
    assert_includes document, 'Validate Datadog Lookup In An Isolated Sandbox'
    assert_includes document, 'slo-rules-engine/datadog-sandbox-smoke/v1'
    assert_includes readme, 'Datadog Sandbox Testing'
    assert_includes document, 'slo-rules-engine/approved-provider-plan/v1'
    assert_includes document, 'stale_approved_plan'
    assert_includes document, 'approved_plan_scope_busy'
    assert_includes document, 'approved_plan_requires_resume'
    assert_includes document, 'execution.replay.status: completed'
    assert_includes document, 'execution.resume.status: completed'
    assert_includes readme, 'plan approve'
    assert_includes readme, 'plan apply'
    assert_includes readme, 'plan resume'
    assert_includes document, 'bundle apply'
    assert_includes document, 'slo-rules-engine/bundle-target-execution/v1'
    assert_includes document, 'bundle_target_execution_incomplete'
    assert_includes document, 'unsupported_bundle_apply_target'
    assert_includes readme, '--output=./work/applied.json'
    assert_includes document, 'bundle verify'
    assert_includes document, 'slo-rules-engine/bundle-target-verification/v1'
    assert_includes document, 'bundle_target_verification_failed'
    assert_includes document, 'unsupported_bundle_verify_target'
    assert_includes readme, '--output=./work/verified.json'
    assert_includes readme, 'target_verification'
    assert_includes document, 'Inspect Live SLO And Error-Budget Status'
    assert_includes document, 'slo-rules-engine/live-slo-status/v1'
    assert_includes document, 'slo-rules-engine/live-slo-status-aggregate/v1'
    assert_includes document, 'slo-rules-engine/live-status-portfolio/v1'
    assert_includes document, '--target-base-url=checkout-api/prometheus_stack='
    assert_includes document, 'coverage_complete'
    assert_includes document, 'runtime URLs'
    assert_includes document, 'error_budget_remaining_ratio'
    assert_includes document, 'missing_telemetry'
    assert_includes document, 'unverifiable'
    assert_includes document, 'GET /api/v1/query'
    assert_includes readme, 'bin/rules-ctl status'
    assert_includes readme, '--max-age-seconds=300'
    assert_includes readme, '--bundle=./work/release-bundle.json'
    assert_includes readme, 'slo-rules-engine/live-slo-status-aggregate/v1'
    assert_includes document, 'Review Sloth Downstream Generated Rules'
    assert_includes document, 'bin/rules-ctl sloth-evidence capture'
    assert_includes document, 'bin/rules-ctl sloth-evidence status'
    assert_includes document, 'slo-rules-engine/sloth-downstream-evidence/v1'
    assert_includes document, 'slo-rules-engine/sloth-downstream-evidence-status/v1'
    assert_includes document, 'stale_generated_rules'
    assert_includes document, 'zero provider reads and writes'
    assert_includes document, '--provider=sloth'
    assert_includes document, '--evidence=./work/sloth-evidence/checkout-api.json'
    assert_includes document, 'invalid_sloth_live_status_evidence'
    assert_includes document, 'Official Sloth MCP Comparison'
    assert_includes document, 'bin/rules-ctl sloth-mcp compare'
    assert_includes document, 'slo-rules-engine/sloth-mcp-comparison/v1'
    assert_includes document, 'authoritative_status_transport: false'
    assert_includes document, 'zero provider writes'
    assert_includes document, 'scripts/structure-report --check'
    assert_includes document, 'unapproved dependency'
    assert_includes document, 'bin/rules-ctl agent invoke providers.list'
    assert_includes document, 'bin/rules-ctl agent invoke validate'
    assert_includes document, 'bin/rules-ctl agent invoke diff'
    assert_includes document, 'slo-rules-engine/agent-command-result/v1'
    assert_includes document, 'structured_invocation: true'
    assert_includes document, 'agent_command_not_executable'
    assert_includes document, 'unsafe_agent_input_path'
    assert_includes document, '`exit_status`'
    assert_includes readme, 'Sloth Downstream Evidence'
    assert_includes readme, 'Official Sloth MCP Comparison'
    assert_includes readme, 'scripts/structure-report --check'
    assert_includes readme, 'bin/rules-ctl agent invoke providers.list'
    assert_includes readme, 'bin/rules-ctl agent invoke validate'
  end

  private

  def sections
    document = File.read(USE_CASES_PATH)
    matches = document.enum_for(:scan, /^## Use Case \d+: .+$/).map { Regexp.last_match }
    matches.each_with_index.to_h do |match, index|
      finish = matches.fetch(index + 1, nil)&.begin(0) || document.length
      [match[0], document[match.end(0)...finish]]
    end
  end
end
