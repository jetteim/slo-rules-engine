# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/slo_rules_engine/cli'

class CliArchitectureTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  COMMAND_MODULES = {
    SloRulesEngine::CLI::CatalogCommands => %i[providers integrations generate_routes],
    SloRulesEngine::CLI::BundleCommands => %i[bundle],
    SloRulesEngine::CLI::JournalCommands => %i[journal],
    SloRulesEngine::CLI::OnboardingCommands => %i[
      validate_handoff
      draft_from_handoff
      onboarding_summary
      onboarding_artifact_index
      review_handoff
    ],
    SloRulesEngine::CLI::PlanCommands => %i[plan],
    SloRulesEngine::CLI::ReportCommands => %i[migration_report model_report],
    SloRulesEngine::CLI::StatusCommands => %i[status],
    SloRulesEngine::CLI::SlothEvidenceCommands => %i[sloth_evidence],
    SloRulesEngine::CLI::TelemetryCommands => %i[
      lookup_telemetry
      discover_telemetry
      candidates
      draft_definition
      recommend_calculation_basis
      reality_check
    ]
  }.freeze

  def test_rules_ctl_composes_every_command_family_from_the_library_boundary
    ancestors = RulesCtl.singleton_class.ancestors

    COMMAND_MODULES.each do |command_module, commands|
      assert_includes ancestors, command_module
      commands.each do |command|
        assert_includes command_module.instance_methods(false), command
      end
    end
    assert_equal File.join(ROOT, 'lib/slo_rules_engine/cli.rb'),
                 RulesCtl.method(:run).source_location.fetch(0)
  end

  def test_executable_is_only_a_thin_library_bootstrap
    executable = File.read(File.join(ROOT, 'bin/rules-ctl'))

    assert_operator executable.lines.length, :<=, 8
    assert_includes executable, "require_relative '../lib/slo_rules_engine/cli'"
    assert_includes executable, 'RulesCtl.run(ARGV)'
    refute_includes executable, 'module RulesCtl'
  end
end
