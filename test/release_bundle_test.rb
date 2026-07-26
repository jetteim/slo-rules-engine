# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/slo_rules_engine'
require_relative 'support/release_bundle_fixtures'

class ReleaseBundleTest < Minitest::Test
  include ReleaseBundleFixtures

  REVIEWER = 'team/payments-sre'
  REVIEWED_AT = '2026-07-26T09:30:00Z'

  def test_builds_stable_versioned_review_ready_bundle
    Dir.mktmpdir do |dir|
      fixture = write_release_bundle_fixture(dir)
      builder = SloRulesEngine::ReleaseBundle::Builder.new

      bundle = builder.build(
        fixture.fetch(:artifact_index),
        reviewer: REVIEWER,
        reviewed_at: REVIEWED_AT
      )
      repeated = builder.build(
        fixture.fetch(:artifact_index),
        reviewer: REVIEWER,
        reviewed_at: REVIEWED_AT
      )

      assert_equal 'slo-rules-engine/release-bundle/v1', bundle.fetch(:schema_version)
      assert_equal 'SLOReleaseBundle', bundle.fetch(:kind)
      assert_match(/\Aslo-bundle-[0-9a-f]{64}\z/, bundle.fetch(:bundle_id))
      assert_equal bundle.fetch(:bundle_id), repeated.fetch(:bundle_id)
      assert_equal 'review_ready', bundle.fetch(:lifecycle)
      assert_equal REVIEWER, bundle.fetch(:review).fetch(:reviewer)
      assert_equal REVIEWED_AT, bundle.fetch(:review).fetch(:reviewed_at)
      assert_equal ['request-latency'],
                   bundle.fetch(:review).fetch(:scopes).fetch(0).fetch(:accepted_candidate_uids)
      assert_equal ['request-traffic'],
                   bundle.fetch(:review).fetch(:scopes).fetch(0).fetch(:rejected_candidate_uids)

      target = bundle.fetch(:targets).fetch(0)
      assert_equal 'checkout-api/prometheus_stack', target.fetch(:uid)
      assert_equal 'manifest_bundle', target.fetch(:automation_mode)
      assert_nil target[:change_plan_artifact_uid]

      assert_equal(
        %w[
          discovery_evidence
          discovery_index
          manifest_review_report
          onboarding_artifact_index
          provider_manifest
          reviewed_definition
          reviewed_handoff
        ],
        bundle.fetch(:artifacts).map { |artifact| artifact.fetch(:kind) }.sort
      )
      bundle.fetch(:artifacts).each do |artifact|
        assert_match(/\A[0-9a-f]{64}\z/, artifact.fetch(:fingerprint))
        refute_nil artifact.fetch(:content)
      end
      assert_equal [], bundle.fetch(:findings)
      assert SloRulesEngine::ReleaseBundle::SchemaValidator.validate(bundle).valid?
    end
  end

  def test_bundle_with_current_change_plan_is_apply_ready
    Dir.mktmpdir do |dir|
      fixture = write_release_bundle_fixture(dir, include_plan: true)

      bundle = SloRulesEngine::ReleaseBundle::Builder.new.build(
        fixture.fetch(:artifact_index),
        reviewer: REVIEWER,
        reviewed_at: REVIEWED_AT,
        plans: { fixture.fetch(:target) => fixture.fetch(:plan) }
      )

      assert_equal 'apply_ready', bundle.fetch(:lifecycle)
      target = bundle.fetch(:targets).fetch(0)
      refute_nil target.fetch(:change_plan_artifact_uid)
      plan = bundle.fetch(:artifacts).find do |artifact|
        artifact.fetch(:uid) == target.fetch(:change_plan_artifact_uid)
      end
      assert_equal 'change_plan', plan.fetch(:kind)
      assert_equal 'dry_run', plan.fetch(:content).fetch('mode')
      assert_equal 4, bundle.fetch(:summary).fetch(:actionable_operations)
    end
  end

  def test_stale_manifest_review_report_blocks_bundle_creation_readiness
    Dir.mktmpdir do |dir|
      fixture = write_release_bundle_fixture(dir)
      manifest = JSON.parse(File.read(fixture.fetch(:manifest)))
      manifest.fetch('review_provenance')['notes'] = ['Changed after report creation.']
      File.write(fixture.fetch(:manifest), JSON.pretty_generate(manifest))

      bundle = SloRulesEngine::ReleaseBundle::Builder.new.build(
        fixture.fetch(:artifact_index),
        reviewer: REVIEWER,
        reviewed_at: REVIEWED_AT
      )

      assert_equal 'stale', bundle.fetch(:lifecycle)
      assert_includes bundle.fetch(:findings).map { |finding| finding.fetch(:code) },
                      'stale_manifest_review_report'
    end
  end

  def test_credential_like_keys_are_rejected_before_content_is_packaged
    Dir.mktmpdir do |dir|
      fixture = write_release_bundle_fixture(dir, include_plan: true)
      plan = JSON.parse(File.read(fixture.fetch(:plan)))
      plan['api_key'] = 'must-not-be-packaged'
      File.write(fixture.fetch(:plan), JSON.pretty_generate(plan))

      error = assert_raises(SloRulesEngine::ReleaseBundle::CredentialError) do
        SloRulesEngine::ReleaseBundle::Builder.new.build(
          fixture.fetch(:artifact_index),
          reviewer: REVIEWER,
          reviewed_at: REVIEWED_AT,
          plans: { fixture.fetch(:target) => fixture.fetch(:plan) }
        )
      end

      assert_equal ['artifacts.change_plan.content.api_key'], error.paths
    end
  end

  def test_status_detects_source_drift_and_embedded_content_tampering
    Dir.mktmpdir do |dir|
      fixture = write_release_bundle_fixture(dir)
      bundle = SloRulesEngine::ReleaseBundle::Builder.new.build(
        fixture.fetch(:artifact_index),
        reviewer: REVIEWER,
        reviewed_at: REVIEWED_AT
      )
      evaluator = SloRulesEngine::ReleaseBundle::StatusEvaluator.new

      clean = evaluator.evaluate(bundle)
      assert_equal true, clean.fetch(:valid)
      assert_equal 'review_ready', clean.fetch(:effective_lifecycle)
      assert_equal 0, clean.fetch(:summary).fetch(:stale_sources)

      File.write(fixture.fetch(:draft), "# changed reviewed definition\n")
      stale = evaluator.evaluate(bundle)
      assert_equal false, stale.fetch(:valid)
      assert_equal 'stale', stale.fetch(:effective_lifecycle)
      assert_equal ['source_artifact_changed'], stale.fetch(:findings).map { |finding| finding.fetch(:code) }

      tampered = Marshal.load(Marshal.dump(bundle))
      manifest = tampered.fetch(:artifacts).find { |artifact| artifact.fetch(:kind) == 'provider_manifest' }
      manifest.fetch(:content)['service'] = 'tampered-service'
      invalid = evaluator.evaluate(tampered)
      assert_equal false, invalid.fetch(:valid)
      assert_equal 'invalid', invalid.fetch(:effective_lifecycle)
      assert_includes invalid.fetch(:findings).map { |finding| finding.fetch(:code) },
                      'artifact_fingerprint_mismatch'
      assert_includes invalid.fetch(:findings).map { |finding| finding.fetch(:code) },
                      'bundle_identity_mismatch'
    end
  end

  def test_schema_rejects_unknown_version_and_lifecycle
    result = SloRulesEngine::ReleaseBundle::SchemaValidator.validate(
      schema_version: 'v2',
      kind: 'SLOReleaseBundle',
      bundle_id: 'invalid',
      lifecycle: 'released',
      review: {},
      targets: [],
      artifacts: [],
      findings: [],
      summary: {}
    )

    refute result.valid?
    assert result.errors.any? { |error| error.path == 'schema_version' }
    assert result.errors.any? { |error| error.path == 'bundle_id' }
    assert result.errors.any? { |error| error.path == 'lifecycle' }
  end
end
