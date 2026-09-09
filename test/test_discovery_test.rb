# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'
require 'tmpdir'

class TestDiscoveryTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def test_aggregate_loads_every_suite_and_exposes_named_tests
    script = <<~RUBY
      require 'json'
      require 'minitest'
      def Minitest.autorun; end
      Minitest.seed = 0
      require_relative 'test/all_test'
      puts JSON.generate(
        files: $LOADED_FEATURES.select { |path| path.start_with?(Dir.pwd + '/test/') && path.end_with?('_test.rb') },
        tests: Minitest::Runnable.runnables.flat_map { |suite| suite.runnable_methods.map { |name| "\#{suite.name}#\#{name}" } }.sort
      )
    RUBY
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-Ilib', '-e', script, chdir: ROOT)
    assert status.success?, stderr
    report = JSON.parse(stdout)
    assert_equal Dir.glob(File.join(ROOT, 'test', '**', '*_test.rb')).sort, report.fetch('files').sort
    identities = report.fetch('tests')
    assert_equal identities.uniq, identities
    %w[AgentTelemetryCommandsTest SlothLiveStatusTest TelemetryBatchDiscoveryTest].each do |suite|
      assert identities.any? { |identity| identity.start_with?(suite + '#') }, "missing named tests for #{suite}"
    end
  end

  def test_new_nested_suite_and_transitive_suite_are_loaded_once
    Dir.mktmpdir('slo-test-discovery-') do |root|
      FileUtils.cp(File.join(ROOT, 'test/all_test.rb'), File.join(root, 'all_test.rb'))
      FileUtils.mkdir_p(File.join(root, 'nested'))
      File.write(File.join(root, 'compatibility_test.rb'), "require_relative 'nested/new_test'\nputs 'compatibility'\n")
      File.write(File.join(root, 'nested/new_test.rb'), "puts 'new nested test'\n")
      File.write(File.join(root, 'support.rb'), "abort 'support file must not run'\n")
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, File.join(root, 'all_test.rb'))
      assert status.success?, stderr
      assert_equal ['new nested test', 'compatibility'], stdout.lines.map(&:strip)
    end
  end
end
