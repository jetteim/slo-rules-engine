# frozen_string_literal: true

require 'minitest/autorun'
load File.expand_path('../bin/rules-ctl', __dir__)

class TelemetryCliCommandsTest < Minitest::Test
  COMMAND_METHODS = %i[
    lookup_telemetry
    discover_telemetry
    candidates
    draft_definition
    recommend_calculation_basis
    reality_check
  ].freeze

  def test_rules_ctl_extends_telemetry_command_module
    assert_includes RulesCtl.singleton_class.ancestors, SloRulesEngine::CLI::TelemetryCommands
    COMMAND_METHODS.each do |method_name|
      assert_includes SloRulesEngine::CLI::TelemetryCommands.instance_methods(false), method_name
    end
  end
end
