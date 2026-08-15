# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/slo_rules_engine/cli'

class AgentInterfaceRoadmapTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  ROADMAP_PATH = File.join(ROOT, 'docs', 'agent-interface-roadmap.md')

  ARTICLE_THEMES = [
    'Raw Structured Requests Alongside Convenience Flags',
    'Runtime Schema Introspection',
    'Context Window Discipline',
    'Input Hardening',
    'Agent Skills',
    'Multiple Surfaces From One Contract',
    'Validation-Only Safety And Response Sanitization'
  ].freeze

  COMMAND_GROUPS = [
    'validate',
    'validate-handoff',
    'generate',
    'manifest-review',
    'apply',
    'diff',
    'import',
    'prune',
    'status',
    'sloth-evidence capture/status',
    'sloth-mcp compare',
    'agent catalog/describe',
    'bundle create/plan/apply/verify/status',
    'journal create/status',
    'plan approve/status/apply/resume',
    'lookup-telemetry',
    'discover-telemetry',
    'providers list',
    'integrations list',
    'generate-routes',
    'candidates',
    'draft-definition',
    'draft-from-handoff',
    'onboarding-summary',
    'onboarding-artifact-index',
    'review-handoff',
    'recommend-calculation-basis',
    'reality-check',
    'migration-report',
    'model-report'
  ].freeze

  def test_roadmap_covers_article_intent_requirements_and_every_current_command
    roadmap = File.read(ROADMAP_PATH)

    assert_includes roadmap, 'https://justin.poehnelt.com/posts/rewrite-your-cli-for-ai-agents/'
    ARTICLE_THEMES.each { |theme| assert_includes roadmap, theme }
    (1..26).each { |number| assert_includes roadmap, format('AICLI-FR-%03d', number) }
    (1..12).each { |number| assert_includes roadmap, format('AICLI-NFR-%03d', number) }
    (1..7).each { |number| assert_includes roadmap, "AICLI-F#{number}" }
    COMMAND_GROUPS.each { |command| assert_includes roadmap, "`#{command}`" }
  end

  def test_roadmap_requires_parity_and_preserves_existing_safety_intent
    roadmap = File.read(ROADMAP_PATH)

    assert_includes roadmap, 'Human CLI'
    assert_includes roadmap, 'Agent CLI'
    assert_includes roadmap, 'single command registry'
    assert_includes roadmap, 'additionalProperties: false'
    assert_includes roadmap, 'field masks'
    assert_includes roadmap, 'NDJSON'
    assert_includes roadmap, 'path traversal'
    assert_includes roadmap, 'control characters'
    assert_includes roadmap, 'embedded query or fragment syntax'
    assert_includes roadmap, 'pre-encoded identifiers'
    assert_includes roadmap, 'prompt-injection-bearing'
    assert_includes roadmap, 'reviewed provenance'
    assert_includes roadmap, 'exact-plan'
    assert_includes roadmap, 'MCP'
    assert_includes roadmap, 'SKILL.md'
    assert_includes roadmap, 'CONTEXT.md'
    assert_includes roadmap, 'headless credentials'
    assert_includes roadmap, 'browser redirects shall not be required'
    assert_includes roadmap, 'encoded exactly once at the transport boundary'
    assert_includes roadmap, 'RULES_CTL_OUTPUT_FORMAT'
    assert_includes roadmap, 'validate_only'
  end

  def test_project_documents_link_the_roadmap_and_enforce_both_cli_interfaces
    agents = File.read(File.join(ROOT, 'AGENTS.md'))
    implementation = File.read(File.join(ROOT, 'docs', 'implementation-plan.md'))
    evolution = File.read(File.join(ROOT, 'docs', 'evolution-plan.md'))
    features = File.read(File.join(ROOT, 'docs', 'features.md'))
    design = File.read(File.join(ROOT, 'docs', 'design.md'))
    use_cases = File.read(File.join(ROOT, 'docs', 'use-cases.md'))
    readme = File.read(File.join(ROOT, 'README.md'))

    assert_includes agents, 'Every CLI change must update both the Human CLI and Agent CLI sub-interfaces'
    assert_includes implementation, '## Phase 14: Agent-Operable Dual CLI And MCP'
    assert_includes implementation, '- [x] **AICLI-F1:**'
    assert_includes evolution, 'Agent-Safe Reliability Automation'
    assert_includes features, '## Planned Agent-Operable Interfaces'
    assert_includes design, 'Human CLI adapter'
    assert_includes design, 'Agent CLI adapter'
    assert_includes design, 'CommandCatalog'
    assert_includes use_cases, '## Use Case 19: Operate The Reviewed Workflow From An AI Agent'
    assert_includes use_cases, '**Delivery status:** partially implemented'
    assert_includes use_cases, 'slo-rules-engine/cli-command-catalog/v1'
    assert_includes readme, 'Agent Interface Roadmap'
    assert_includes readme, '40-command catalog'
    assert_includes File.read(ROADMAP_PATH), '**AICLI-F1 status:** implemented'
    assert_includes File.read(ROADMAP_PATH), 'first zero-I/O `agent invoke` vertical slice'
    assert_includes File.read(ROADMAP_PATH), '`structured_invocation`'
    assert_includes readme, '`agent invoke` is implemented'
  end

  def test_current_human_cli_registry_and_usage_are_not_missing_from_the_roadmap
    cli = File.read(File.join(ROOT, 'lib', 'slo_rules_engine', 'cli.rb'))
    registry = SloRulesEngine::CLI::CommandRegistry.default

    registry.definitions.each do |definition|
      root = definition.human_path.first
      assert COMMAND_GROUPS.any? { |entry| entry.split.first == root },
             "missing #{definition.id} from roadmap parity inventory"
    end
    assert_includes cli, 'bin/rules-ctl lookup-telemetry --provider=<provider>'
  end
end
