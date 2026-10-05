# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/slo_rules_engine/cli'
require_relative 'support/release_bundle_fixtures'

class ProviderWorkflowCompatibilityTest < Minitest::Test
  include ReleaseBundleFixtures

  def test_provider_validation_preserves_order_and_constructs_core_once
    owners.each do |owner|
      calls = []
      constructions = 0
      core = validator(:core, calls)
      provider = validator(:provider, calls)
      result = with_core_validator(-> { constructions += 1; core }) do
        owner.send(:validate_for_provider, %i[first second], provider)
      end
      expected_errors = %w[first.core first.provider second.core second.provider].map { |path| { path: path, message: 'error' } }
      expected_warnings = %w[first.core first.provider second.core second.provider].map { |path| { path: path, message: 'warning' } }
      assert_equal({ valid: false, errors: expected_errors, warnings: expected_warnings }, result)
      assert_equal [[:core, :first], [:provider, :first], [:core, :second], [:provider, :second]], calls
      assert_equal 1, constructions
    end
  end

  def test_validation_keeps_warning_only_and_empty_input_success
    owners.each do |owner|
      core = validator(:core, [], errors: false)
      provider = validator(:provider, [], errors: false)
      with_core_validator(core) do
        result = owner.send(:validate_for_provider, [:first], provider)
        assert result.fetch(:valid)
        assert_empty result.fetch(:errors)
        assert_equal %w[first.core first.provider], result.fetch(:warnings).map { |finding| finding[:path] }
        assert_equal({ valid: true, errors: [], warnings: [] }, owner.send(:validate_for_provider, [], provider))
      end
    end
  end

  def test_validation_propagates_provider_failures_after_core_validation
    owners.each do |owner|
      calls = []
      provider = Object.new
      provider.define_singleton_method(:validate) { |_definition| raise ArgumentError, 'fixture provider failure' }
      with_core_validator(validator(:core, calls)) do
        error = assert_raises(ArgumentError) { owner.send(:validate_for_provider, %i[first second], provider) }
        assert_equal 'fixture provider failure', error.message
        assert_equal [[:core, :first]], calls
      end
    end
  end

  def test_validation_retains_the_neutral_validator_constant_lookup
    application = SloRulesEngine::Application
    shadow = Class.new
    shadow.define_singleton_method(:new) { raise 'wrong validator namespace' }
    application.const_set(:CoreValidator, shadow)
    core = validator(:core, [], errors: false)
    provider = validator(:provider, [], errors: false)
    with_core_validator(core) do
      owners.each { |owner| assert owner.send(:validate_for_provider, [:first], provider).fetch(:valid) }
    end
  ensure
    application.send(:remove_const, :CoreValidator) if application.const_defined?(:CoreValidator, false)
  end

  def test_legacy_writer_entry_points_preserve_bytes_and_return_values
    manifest = reviewed_provider_manifest('prometheus_stack')
    provider = SloRulesEngine.default_provider_registry.fetch('prometheus_stack')
    Dir.mktmpdir('workflow-compatibility') do |dir|
      plain = File.join(dir, 'plain')
      assert_nil RulesCtl.write_provider_manifests(plain, [manifest])
      path = File.join(plain, 'checkout-api', 'prometheus_stack', 'manifest.json')
      assert_equal JSON.pretty_generate(manifest), File.read(path)
      refute File.exist?(File.join(plain, 'manifest-review'))

      reviewed = File.join(dir, 'reviewed')
      count = RulesCtl.write_provider_manifests(reviewed, [manifest], provider: provider)
      report_path = File.join(reviewed, 'manifest-review', 'prometheus_stack.json')
      expected = SloRulesEngine::ManifestReviewQueue::ReportBuilder.new.build([manifest], provider: provider.key)
      expected[:report] = { path: report_path }
      assert_equal JSON.pretty_generate(expected), File.read(report_path)
      assert_equal File.size(report_path), count
      assert_equal File.size(report_path), RulesCtl.write_manifest_review_report(reviewed, [manifest], provider: provider, handoff_dir: nil)
    end
  end

  private

  def with_core_validator(value)
    singleton = SloRulesEngine::CoreValidator.singleton_class
    originally_owned = singleton.instance_methods(false).include?(:new)
    original = SloRulesEngine::CoreValidator.method(:new)
    singleton.define_method(:new) { value.respond_to?(:call) ? value.call : value }
    yield
  ensure
    if originally_owned
      singleton.define_method(:new, original)
    else
      singleton.remove_method(:new)
    end
  end

  def owners
    [RulesCtl, Object.new.extend(SloRulesEngine::Application::ProviderGenerationSupport),
     SloRulesEngine::Application::DiffProviderState.new]
  end

  def validator(name, calls, errors: true)
    validator = Object.new
    validator.define_singleton_method(:validate) do |definition|
      calls << [name, definition]
      result = Struct.new(:errors, :warnings)
      path = "#{definition}.#{name}"
      result.new(errors ? [{ path: path, message: 'error' }] : [], [{ path: path, message: 'warning' }])
    end
    validator
  end
end
