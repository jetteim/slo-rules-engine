# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/slo_rules_engine'

class ManifestSchemaTest < Minitest::Test
  def setup
    SloRulesEngine.clear_definitions
    load File.expand_path('../examples/services/checkout.rb', __dir__)
    @definition = SloRulesEngine.definitions.fetch(0)
  end

  def test_generated_manifests_validate_for_builtin_providers
    registry = SloRulesEngine.default_provider_registry

    registry.list.each do |provider|
      manifest = provider.generate(@definition).to_h.merge(service: @definition.service)

      result = SloRulesEngine::ManifestSchemaValidator.validate(manifest)

      assert result.valid?, "expected #{provider.key} manifest to be valid, got #{result.errors.map(&:to_h)}"
    end
  end

  def test_datadog_manifest_requires_success_selector_for_apply_ready_slo
    manifest = SloRulesEngine.default_provider_registry.fetch('datadog').generate(@definition).to_h.merge(service: @definition.service)
    manifest.fetch(:artifacts).fetch(:slos).fetch(0).fetch(:query).delete(:success_selector)

    result = SloRulesEngine::ManifestSchemaValidator.validate(manifest)

    refute result.valid?
    assert result.errors.any? do |error|
      error.path == 'artifacts.slos[0].query.success_selector' && error.message == 'is required'
    end
  end
end
