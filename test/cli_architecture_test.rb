# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/slo_rules_engine/cli'

class CliArchitectureTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def test_rules_ctl_composes_every_command_family_from_the_library_boundary
    ancestors = RulesCtl.singleton_class.ancestors
    registry = SloRulesEngine::CLI::CommandRegistry.default
    modules = command_modules

    modules.each do |command_module|
      assert_includes ancestors, command_module
      owned_adapters = registry.definitions.map(&:adapter).uniq.select do |adapter|
        RulesCtl.method(adapter).owner == command_module
      end
      refute_empty owned_adapters, "#{command_module} must own a registered command adapter"
    end

    allowed_owners = modules + [RulesCtl.singleton_class]
    registry.definitions.map(&:adapter).uniq.each do |adapter|
      assert_includes allowed_owners, RulesCtl.method(adapter).owner, adapter
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

  private

  def command_modules
    Dir.glob(File.join(ROOT, 'lib/slo_rules_engine/cli/*_commands.rb')).sort.map do |path|
      constant_name = File.basename(path, '.rb').split('_').map(&:capitalize).join
      SloRulesEngine::CLI.const_get(constant_name, false)
    end
  end
end
