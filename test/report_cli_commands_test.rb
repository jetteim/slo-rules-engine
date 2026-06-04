# frozen_string_literal: true

require 'minitest/autorun'
load File.expand_path('../bin/rules-ctl', __dir__)

class ReportCliCommandsTest < Minitest::Test
  def test_rules_ctl_extends_report_command_module
    assert_includes RulesCtl.singleton_class.ancestors, SloRulesEngine::CLI::ReportCommands
    assert_includes SloRulesEngine::CLI::ReportCommands.instance_methods(false), :migration_report
    assert_includes SloRulesEngine::CLI::ReportCommands.instance_methods(false), :model_report
  end
end
