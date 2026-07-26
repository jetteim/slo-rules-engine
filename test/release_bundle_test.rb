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

  def test_plans_review_ready_bundle_without_mutating_predecessor_or_managed_state
    Dir.mktmpdir do |dir|
      fixture = write_release_bundle_fixture(dir)
      predecessor = SloRulesEngine::ReleaseBundle::Builder.new.build(
        fixture.fetch(:artifact_index),
        reviewer: REVIEWER,
        reviewed_at: REVIEWED_AT
      )
      original = Marshal.load(Marshal.dump(predecessor))
      output_dir = File.join(dir, 'managed')

      planned = SloRulesEngine::ReleaseBundle::Planner.new.plan(
        predecessor,
        target_runtime: {
          fixture.fetch(:target) => { output_dir: output_dir }
        }
      )

      assert_equal original, predecessor
      refute File.exist?(output_dir)
      assert_equal 'review_ready', predecessor.fetch(:lifecycle)
      assert_equal 'apply_ready', planned.fetch(:lifecycle)
      refute_equal predecessor.fetch(:bundle_id), planned.fetch(:bundle_id)
      assert_equal predecessor.fetch(:bundle_id), planned.fetch(:transition).fetch(:predecessor_bundle_id)
      assert_equal 'plan', planned.fetch(:transition).fetch(:action)

      target = planned.fetch(:targets).fetch(0)
      plan = planned.fetch(:artifacts).find do |artifact|
        artifact.fetch(:uid) == target.fetch(:change_plan_artifact_uid)
      end
      assert_equal 'generated', plan.fetch(:source).fetch(:type)
      assert_equal predecessor.fetch(:bundle_id), plan.fetch(:source).fetch(:predecessor_bundle_id)
      assert_equal Array.new(4, 'write'), plan.fetch(:content).fetch('operations').map { |operation| operation.fetch('action') }
      assert_equal 'ProviderStatePlan', plan.fetch(:content).fetch('state_contract').fetch('kind')
      assert_equal 'checkout-api', plan.fetch(:content).fetch('state_contract').fetch('service')

      summary = planned.fetch(:summary)
      assert_equal 4, summary.fetch(:total_operations)
      assert_equal 4, summary.fetch(:actionable_operations)
      assert_equal 0, summary.fetch(:destructive_operations)
      assert_equal 0, summary.fetch(:risky_operations)
      assert_equal 'none', summary.fetch(:highest_risk_level)
      assert_equal(
        {
          provider: 'prometheus_stack',
          target_count: 1,
          change_plan_count: 1,
          total_operations: 4,
          actionable_operations: 4,
          destructive_operations: 0,
          risky_operations: 0,
          highest_risk_level: 'none',
          operations_by_action: { 'write' => 4 },
          operations_by_target: {
            'manifest_file' => 1,
            'prometheus_stack.prometheus_rule' => 1,
            'prometheus_stack.grafana_dashboard' => 1,
            'prometheus_stack.alertmanager_route_intent' => 1
          },
          operations_by_risk: {}
        },
        summary.fetch(:provider_summaries).fetch(0)
      )

      status = SloRulesEngine::ReleaseBundle::StatusEvaluator.new.evaluate(planned)
      assert_equal true, status.fetch(:valid)
      assert_equal 'apply_ready', status.fetch(:effective_lifecycle)
      assert_equal 0, status.fetch(:summary).fetch(:stale_sources)

      tampered = Marshal.load(Marshal.dump(planned))
      generated = tampered.fetch(:artifacts).find { |artifact| artifact.fetch(:kind) == 'change_plan' }
      generated.fetch(:source)[:target_uid] = 'other/prometheus_stack'
      invalid = SloRulesEngine::ReleaseBundle::StatusEvaluator.new.evaluate(tampered)
      assert_equal false, invalid.fetch(:valid)
      assert_includes invalid.fetch(:findings).map { |finding| finding.fetch(:code) },
                      'bundle_identity_mismatch'
    end
  end

  def test_bundle_plan_reports_noop_operations_from_current_managed_state
    Dir.mktmpdir do |dir|
      fixture = write_release_bundle_fixture(dir)
      predecessor = SloRulesEngine::ReleaseBundle::Builder.new.build(
        fixture.fetch(:artifact_index),
        reviewer: REVIEWER,
        reviewed_at: REVIEWED_AT
      )
      output_dir = File.join(dir, 'managed')
      manifest = JSON.parse(File.read(fixture.fetch(:manifest)), symbolize_names: true)
      SloRulesEngine::Appliers::ManifestBundle.new(output_dir: output_dir).apply(manifest)

      planned = SloRulesEngine::ReleaseBundle::Planner.new.plan(
        predecessor,
        target_runtime: {
          fixture.fetch(:target) => { output_dir: output_dir }
        }
      )

      assert_equal 4, planned.fetch(:summary).fetch(:total_operations)
      assert_equal 0, planned.fetch(:summary).fetch(:actionable_operations)
      assert_equal({ 'noop' => 4 },
                   planned.fetch(:summary).fetch(:provider_summaries).fetch(0).fetch(:operations_by_action))
    end
  end

  def test_bundle_plan_rejects_stale_predecessor_before_planning
    Dir.mktmpdir do |dir|
      fixture = write_release_bundle_fixture(dir)
      predecessor = SloRulesEngine::ReleaseBundle::Builder.new.build(
        fixture.fetch(:artifact_index),
        reviewer: REVIEWER,
        reviewed_at: REVIEWED_AT
      )
      File.write(fixture.fetch(:draft), "# changed before planning\n")

      error = assert_raises(SloRulesEngine::ReleaseBundle::PlannerError) do
        SloRulesEngine::ReleaseBundle::Planner.new.plan(
          predecessor,
          target_runtime: {
            fixture.fetch(:target) => { output_dir: File.join(dir, 'managed') }
          }
        )
      end

      assert_equal 'stale_bundle', error.code
      assert_includes error.findings.map { |finding| finding.fetch(:code) }, 'source_artifact_changed'
    end
  end

  def test_bundle_plan_requires_explicit_runtime_configuration_for_every_target
    Dir.mktmpdir do |dir|
      fixture = write_release_bundle_fixture(dir)
      predecessor = SloRulesEngine::ReleaseBundle::Builder.new.build(
        fixture.fetch(:artifact_index),
        reviewer: REVIEWER,
        reviewed_at: REVIEWED_AT
      )

      error = assert_raises(SloRulesEngine::ReleaseBundle::PlannerError) do
        SloRulesEngine::ReleaseBundle::Planner.new.plan(predecessor, target_runtime: {})
      end

      assert_equal 'missing_target_runtime', error.code
      assert_equal ['targets[checkout-api/prometheus_stack].runtime'], error.findings.map { |finding| finding.fetch(:path) }
    end
  end

  def test_summary_builder_aggregates_changes_and_risk_by_provider
    targets = [
      {
        uid: 'checkout-api/prometheus_stack',
        provider: 'prometheus_stack',
        change_plan_artifact_uid: 'change-plan:checkout-api/prometheus_stack'
      },
      {
        uid: 'checkout-api/datadog',
        provider: 'datadog',
        change_plan_artifact_uid: 'change-plan:checkout-api/datadog'
      }
    ]
    artifacts = [
      change_plan_artifact(
        'checkout-api/prometheus_stack',
        'prometheus_stack',
        [
          { action: 'write', target: 'manifest_file' },
          { action: 'noop', target: 'prometheus_stack.prometheus_rule' }
        ]
      ),
      change_plan_artifact(
        'checkout-api/datadog',
        'datadog',
        [
          { action: 'update', target: 'datadog.slo', risk: { level: 'medium' } },
          { action: 'recreate', target: 'datadog.monitor', risk: { level: 'high' } }
        ]
      )
    ]

    summary = SloRulesEngine::ReleaseBundle::SummaryBuilder.new.build(
      review: { scopes: [{ label: 'checkout-prod' }] },
      targets: targets,
      artifacts: artifacts,
      findings: []
    )

    assert_equal 4, summary.fetch(:total_operations)
    assert_equal 3, summary.fetch(:actionable_operations)
    assert_equal 1, summary.fetch(:destructive_operations)
    assert_equal 2, summary.fetch(:risky_operations)
    assert_equal 'high', summary.fetch(:highest_risk_level)
    assert_equal %w[datadog prometheus_stack],
                 summary.fetch(:provider_summaries).map { |provider| provider.fetch(:provider) }
    datadog = summary.fetch(:provider_summaries).fetch(0)
    assert_equal 2, datadog.fetch(:total_operations)
    assert_equal 2, datadog.fetch(:actionable_operations)
    assert_equal 1, datadog.fetch(:destructive_operations)
    assert_equal 2, datadog.fetch(:risky_operations)
    assert_equal 'high', datadog.fetch(:highest_risk_level)
    assert_equal({ 'high' => 1, 'medium' => 1 }, datadog.fetch(:operations_by_risk))
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

  private

  def change_plan_artifact(target_uid, provider, operations)
    {
      uid: "change-plan:#{target_uid}",
      kind: 'change_plan',
      provider: provider,
      content: {
        provider: provider,
        mode: 'dry_run',
        operations: operations
      }
    }
  end
end
