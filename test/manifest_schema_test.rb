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

  def test_manifest_schema_validates_review_provenance_when_present
    manifest = SloRulesEngine.default_provider_registry.fetch('datadog').generate(@definition).to_h.merge(
      service: @definition.service,
      review_provenance: {
        label: 'checkout-prod',
        provider: 'datadog',
        accepted_candidate_uids: ['request-latency'],
        notes: ['Latency accepted.']
      }
    )

    result = SloRulesEngine::ManifestSchemaValidator.validate(manifest)

    assert result.valid?, result.errors.map(&:to_h).inspect

    manifest.fetch(:review_provenance).delete(:accepted_candidate_uids)
    result = SloRulesEngine::ManifestSchemaValidator.validate(manifest)

    refute result.valid?
    assert result.errors.any? { |error| error.path == 'review_provenance.accepted_candidate_uids' }
  end

  def test_manifest_review_evidence_requires_review_provenance
    manifest = SloRulesEngine.default_provider_registry.fetch('datadog').generate(@definition).to_h.merge(service: @definition.service)

    result = SloRulesEngine::ManifestReviewEvidenceValidator.validate([manifest])

    refute result.valid?
    assert result.errors.any? { |error| error.path == 'manifests[0].review_provenance' }
  end

  def test_manifest_review_evidence_requires_accepted_candidate
    manifest = SloRulesEngine.default_provider_registry.fetch('datadog').generate(@definition).to_h.merge(
      service: @definition.service,
      review_provenance: {
        label: 'checkout-prod',
        provider: 'datadog',
        accepted_candidate_uids: []
      }
    )

    result = SloRulesEngine::ManifestReviewEvidenceValidator.validate([manifest])

    refute result.valid?
    assert result.errors.any? { |error| error.path == 'manifests[0].review_provenance.accepted_candidate_uids' }
  end
end
