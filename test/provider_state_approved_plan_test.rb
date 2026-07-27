# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'tmpdir'
require_relative 'support/release_bundle_fixtures'

class ProviderStateApprovedPlanTest < Minitest::Test
  include ReleaseBundleFixtures

  REVIEWER = 'team/payments-sre'
  REVIEWED_AT = '2026-07-27T14:00:00Z'

  def test_builder_locks_apply_ready_bundle_evidence_and_provider_plan
    Dir.mktmpdir do |dir|
      fixture, bundle, managed_dir = planned_bundle(dir)
      builder = SloRulesEngine::ProviderState::ApprovedPlan::Builder.new

      first = builder.build(
        bundle,
        target_uid: fixture.fetch(:target),
        reviewer: REVIEWER,
        reviewed_at: REVIEWED_AT,
        notes: ['Approved after reviewing the managed-file changes.']
      )
      second = builder.build(
        bundle,
        target_uid: fixture.fetch(:target),
        reviewer: REVIEWER,
        reviewed_at: REVIEWED_AT,
        notes: ['Approved after reviewing the managed-file changes.']
      )
      loaded = SloRulesEngine::ProviderState::ApprovedPlan::Loader.new.load(first)

      assert_equal 'slo-rules-engine/approved-provider-plan/v1', first.fetch(:schema_version)
      assert_equal 'ApprovedProviderPlan', first.fetch(:kind)
      assert_match(/\Aapproved-provider-plan-[0-9a-f]{64}\z/, first.fetch(:approved_plan_id))
      assert_equal first, second
      assert_equal first, loaded.to_h
      assert_equal fixture.fetch(:target), first.dig(:target, :uid)
      assert_equal 'prometheus_stack', first.dig(:target, :provider)
      assert_equal File.expand_path(managed_dir), first.dig(:runtime, :output_dir)
      assert_equal bundle.fetch(:bundle_id), first.dig(:source_bundle, :bundle_id)
      assert_equal REVIEWER, first.dig(:approval, :reviewer)
      assert_equal REVIEWED_AT, first.dig(:approval, :reviewed_at)

      evidence = first.fetch(:evidence)
      assert_equal bundle.fetch(:review), evidence.fetch(:bundle_review)
      assert_sha256 evidence.fetch(:bundle_review_fingerprint)
      %i[change_plan provider_manifest manifest_review_report reviewed_handoff].each do |kind|
        assert_sha256 evidence.fetch(kind).fetch(:fingerprint)
        refute_empty evidence.fetch(kind).fetch(:artifact_uid)
      end

      provider_plan = loaded.provider_plan
      assert_equal 'dry_run', provider_plan.mode
      assert_equal 'prometheus_stack', provider_plan.provider
      assert_equal 'checkout-api', provider_plan.service
      assert_equal first.dig(:evidence, :change_plan, :provider_plan_fingerprint),
                   provider_plan.fingerprint
    end
  end

  def test_builder_rejects_stale_bundle_sources
    Dir.mktmpdir do |dir|
      fixture, bundle, = planned_bundle(dir)
      File.write(fixture.fetch(:draft), "# changed after bundle planning\n")

      error = assert_raises(SloRulesEngine::ProviderState::ApprovedPlan::Error) do
        SloRulesEngine::ProviderState::ApprovedPlan::Builder.new.build(
          bundle,
          target_uid: fixture.fetch(:target),
          reviewer: REVIEWER,
          reviewed_at: REVIEWED_AT
        )
      end

      assert_equal 'stale_source_bundle', error.code
      assert_includes error.findings.map { |finding| finding.fetch(:code) }, 'source_artifact_changed'
    end
  end

  def test_builder_rejects_live_api_targets_until_backend_recheck_is_supported
    Dir.mktmpdir do |dir|
      fixture, bundle, = planned_bundle(dir)
      target = bundle.fetch(:targets).fetch(0)
      target[:provider] = 'datadog'
      target[:automation_mode] = 'live_api'
      bundle[:bundle_id] = SloRulesEngine::ReleaseBundle::Fingerprint.bundle_id(bundle)

      error = assert_raises(SloRulesEngine::ProviderState::ApprovedPlan::Error) do
        SloRulesEngine::ProviderState::ApprovedPlan::Builder.new.build(
          bundle,
          target_uid: fixture.fetch(:target),
          reviewer: REVIEWER,
          reviewed_at: REVIEWED_AT
        )
      end

      assert_equal 'unsupported_exact_plan_provider', error.code
    end
  end

  def test_loader_rejects_tampered_plan_and_credential_like_keys
    Dir.mktmpdir do |dir|
      fixture, bundle, = planned_bundle(dir)
      approved = SloRulesEngine::ProviderState::ApprovedPlan::Builder.new.build(
        bundle,
        target_uid: fixture.fetch(:target),
        reviewer: REVIEWER,
        reviewed_at: REVIEWED_AT
      )

      tampered_plan = JSON.parse(JSON.generate(approved), symbolize_names: true)
      tampered_plan[:provider_plan][:desired_state][:resources][:service] = 'tampered'
      plan_error = assert_raises(SloRulesEngine::ProviderState::ApprovedPlan::Error) do
        SloRulesEngine::ProviderState::ApprovedPlan::Loader.new.load(tampered_plan)
      end
      assert_equal 'invalid_provider_plan', plan_error.code

      credential_bearing = JSON.parse(JSON.generate(approved), symbolize_names: true)
      credential_bearing[:credentials] = { token: 'must-not-be-persisted' }
      credential_error = assert_raises(SloRulesEngine::ProviderState::ApprovedPlan::Error) do
        SloRulesEngine::ProviderState::ApprovedPlan::Loader.new.load(credential_bearing)
      end
      assert_equal 'credential_material_forbidden', credential_error.code
      assert_equal 'approved_plan.credentials', credential_error.path
    end
  end

  def test_store_revalidates_hashes_before_writing
    Dir.mktmpdir do |dir|
      fixture, bundle, = planned_bundle(dir)
      approved = SloRulesEngine::ProviderState::ApprovedPlan::Builder.new.build(
        bundle,
        target_uid: fixture.fetch(:target),
        reviewer: REVIEWER,
        reviewed_at: REVIEWED_AT
      )
      approved[:provider_plan][:fingerprint] = '0' * 64
      output_path = File.join(dir, 'approved-plan.json')

      error = assert_raises(SloRulesEngine::ProviderState::ApprovedPlan::Error) do
        SloRulesEngine::ProviderState::ApprovedPlan::Store.new.write(output_path, approved)
      end

      assert_equal 'invalid_provider_plan', error.code
      refute File.exist?(output_path)
    end
  end

  private

  def planned_bundle(dir)
    fixture = write_release_bundle_fixture(dir)
    review_ready = SloRulesEngine::ReleaseBundle::Builder.new.build(
      fixture.fetch(:artifact_index),
      reviewer: REVIEWER,
      reviewed_at: REVIEWED_AT
    )
    managed_dir = File.join(dir, 'managed')
    planned = SloRulesEngine::ReleaseBundle::Planner.new.plan(
      review_ready,
      target_runtime: {
        fixture.fetch(:target) => {
          output_dir: managed_dir
        }
      }
    )
    [fixture, planned, managed_dir]
  end

  def assert_sha256(value)
    assert_match(/\A[0-9a-f]{64}\z/, value)
  end
end
