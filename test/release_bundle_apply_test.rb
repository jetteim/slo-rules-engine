# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'tmpdir'
require_relative 'support/release_bundle_fixtures'

class ReleaseBundleApplyTest < Minitest::Test
  include ReleaseBundleFixtures

  REVIEWER = 'team/payments-sre'
  REVIEWED_AT = '2026-07-27T09:30:00Z'

  def test_applies_every_file_target_in_uid_order_and_builds_an_immutable_successor
    Dir.mktmpdir do |dir|
      bundle, documents = planned_bundle_and_approvals(dir)
      executor = RecordingExecutor.new

      applied = SloRulesEngine::ReleaseBundle::Applier.new(executor: executor).apply(
        bundle,
        approved_plans: documents
      )

      assert_equal documents.keys.sort, executor.target_uids
      assert_equal 'applied', applied.fetch(:lifecycle)
      assert_equal(
        {
          action: 'apply',
          predecessor_bundle_id: bundle.fetch(:bundle_id),
          predecessor_lifecycle: 'apply_ready'
        },
        applied.fetch(:transition)
      )
      assert_equal 2, applied.fetch(:summary).fetch(:execution_count)
      assert_equal({ 'succeeded' => 2 }, applied.fetch(:summary).fetch(:executions_by_status))
      assert_equal 2, applied.fetch(:artifacts).count { |artifact| artifact.fetch(:kind) == 'execution_result' }
      assert applied.fetch(:targets).all? { |target| target.fetch(:execution_artifact_uid) }
      assert SloRulesEngine::ReleaseBundle::SchemaValidator.validate(applied).valid?
      assert_equal 'applied',
                   SloRulesEngine::ReleaseBundle::StatusEvaluator.new.evaluate(applied).fetch(:effective_lifecycle)
      refute_equal bundle.fetch(:bundle_id), applied.fetch(:bundle_id)
      assert_equal 'apply_ready', bundle.fetch(:lifecycle)

      nonterminal = Marshal.load(Marshal.dump(applied))
      execution = nonterminal.fetch(:artifacts).find { |artifact| artifact.fetch(:kind) == 'execution_result' }
      execution.fetch(:content).fetch(:result)[:status] = 'partial'
      execution[:fingerprint] = SloRulesEngine::ReleaseBundle::Fingerprint.artifact_content(execution)
      nonterminal[:bundle_id] = SloRulesEngine::ReleaseBundle::Fingerprint.bundle_id(nonterminal)
      schema = SloRulesEngine::ReleaseBundle::SchemaValidator.validate(nonterminal)
      refute schema.valid?
      assert schema.errors.any? { |error| error.path.end_with?('.execution.result.status') }
    end
  end

  def test_rejects_incomplete_approval_coverage_before_any_target_executes
    Dir.mktmpdir do |dir|
      bundle, documents = planned_bundle_and_approvals(dir)
      documents.delete(documents.keys.last)
      executor = RecordingExecutor.new

      error = assert_raises(SloRulesEngine::ReleaseBundle::ApplyError) do
        SloRulesEngine::ReleaseBundle::Applier.new(executor: executor).apply(
          bundle,
          approved_plans: documents
        )
      end

      assert_equal 'incomplete_approved_plan_coverage', error.code
      assert_empty executor.target_uids
      assert_equal ['missing_approved_plan'], error.findings.map { |finding| finding.fetch(:code) }
    end
  end

  def test_stops_after_first_incomplete_target_and_reports_completed_execution
    Dir.mktmpdir do |dir|
      bundle, documents = planned_bundle_and_approvals(dir)
      ordered = documents.keys.sort
      executor = RecordingExecutor.new(statuses: {
        ordered.fetch(0) => 'succeeded',
        ordered.fetch(1) => 'partial'
      })

      error = assert_raises(SloRulesEngine::ReleaseBundle::ApplyError) do
        SloRulesEngine::ReleaseBundle::Applier.new(executor: executor).apply(
          bundle,
          approved_plans: documents
        )
      end

      assert_equal 'bundle_target_execution_incomplete', error.code
      assert_equal ordered, executor.target_uids
      assert_equal ordered.fetch(1), error.target_uid
      assert_equal [ordered.fetch(0)], error.completed_targets.map { |entry| entry.fetch(:target_uid) }
    end
  end

  def test_rejects_live_api_targets_before_loading_execution_coverage
    Dir.mktmpdir do |dir|
      bundle, documents = planned_bundle_and_approvals(dir)
      live_bundle = Marshal.load(Marshal.dump(bundle))
      live_bundle.fetch(:targets).last[:automation_mode] = 'live_api'
      live_bundle[:bundle_id] = SloRulesEngine::ReleaseBundle::Fingerprint.bundle_id(live_bundle)
      executor = RecordingExecutor.new

      error = assert_raises(SloRulesEngine::ReleaseBundle::ApplyError) do
        SloRulesEngine::ReleaseBundle::Applier.new(executor: executor).apply(
          live_bundle,
          approved_plans: documents
        )
      end

      assert_equal 'unsupported_bundle_apply_target', error.code
      assert_empty executor.target_uids
    end
  end

  def test_rejects_approval_from_another_bundle_before_any_target_executes
    Dir.mktmpdir do |dir|
      bundle, documents = planned_bundle_and_approvals(dir)
      target_uid = documents.keys.first
      mismatched = documents.fetch(target_uid).to_h
      mismatched[:source_bundle][:bundle_id] = "slo-bundle-#{'f' * 64}"
      identity = mismatched.reject { |key, _value| key == :approved_plan_id }
      mismatched[:approved_plan_id] = "approved-provider-plan-#{
        SloRulesEngine::ProviderState::Fingerprint.content(identity)
      }"
      documents[target_uid] = mismatched
      executor = RecordingExecutor.new

      error = assert_raises(SloRulesEngine::ReleaseBundle::ApplyError) do
        SloRulesEngine::ReleaseBundle::Applier.new(executor: executor).apply(
          bundle,
          approved_plans: documents
        )
      end

      assert_equal 'approved_plan_bundle_mismatch', error.code
      assert_empty executor.target_uids
      assert_includes error.findings.map { |finding| finding.fetch(:code) },
                      'approved_plan_source_bundle_mismatch'
    end
  end

  private

  def planned_bundle_and_approvals(dir)
    fixture = write_release_bundle_fixture(
      dir,
      providers: %w[prometheus_stack sloth]
    )
    review_ready = SloRulesEngine::ReleaseBundle::Builder.new.build(
      fixture.fetch(:artifact_index),
      reviewer: REVIEWER,
      reviewed_at: REVIEWED_AT
    )
    runtime = fixture.fetch(:targets).to_h do |target_uid|
      [target_uid, { output_dir: File.join(dir, 'managed') }]
    end
    bundle = SloRulesEngine::ReleaseBundle::Planner.new.plan(
      review_ready,
      target_runtime: runtime
    )
    documents = fixture.fetch(:targets).to_h do |target_uid|
      payload = SloRulesEngine::ProviderState::ApprovedPlan::Builder.new.build(
        bundle,
        target_uid: target_uid,
        reviewer: REVIEWER,
        reviewed_at: REVIEWED_AT
      )
      [
        target_uid,
        SloRulesEngine::ProviderState::ApprovedPlan::Loader.new.load(payload)
      ]
    end
    [bundle, documents]
  end

  class RecordingExecutor
    attr_reader :target_uids

    def initialize(statuses: {})
      @statuses = statuses
      @target_uids = []
    end

    def execute(document)
      target_uid = SloRulesEngine::ProviderState::Value.fetch(document.target, :uid)
      @target_uids << target_uid
      status = @statuses.fetch(target_uid, 'succeeded')
      execution = {
        approved_plan: document.reference,
        operation_journal: {
          schema_version: SloRulesEngine::ProviderState::JOURNAL_SCHEMA_VERSION,
          journal_id: "operation-journal-#{'a' * 64}",
          path: "/tmp/#{target_uid.tr('/', '-')}.json",
          status: status == 'partial' ? 'partial' : 'succeeded',
          fingerprint: 'b' * 64
        },
        result: {
          schema_version: SloRulesEngine::ProviderState::SCHEMA_VERSION,
          kind: 'ProviderStateResult',
          status: status,
          provider: SloRulesEngine::ProviderState::Value.fetch(document.target, :provider),
          service: SloRulesEngine::ProviderState::Value.fetch(document.target, :service)
        }
      }
      Struct.new(:execution).new(execution)
    end
  end
end
