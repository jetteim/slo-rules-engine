# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require_relative 'support/release_bundle_fixtures'

class ProviderStateExactPlanCliTest < Minitest::Test
  include ReleaseBundleFixtures

  ROOT = File.expand_path('..', __dir__)
  REVIEWER = 'team/payments-sre'
  REVIEWED_AT = '2026-07-27T14:00:00Z'

  def test_approve_status_and_apply_execute_the_approved_file_plan
    Dir.mktmpdir do |dir|
      fixture, bundle_path, managed_dir = write_planned_bundle(dir)
      approved_path = File.join(dir, 'approved-plan.json')
      journal_dir = File.join(dir, 'journals')

      approved, approve_stderr, approve_status = command_json(
        'plan',
        'approve',
        bundle_path,
        "--target=#{fixture.fetch(:target)}",
        "--reviewer=#{REVIEWER}",
        "--reviewed-at=#{REVIEWED_AT}",
        '--note=Managed-file changes reviewed.',
        "--output=#{approved_path}"
      )
      assert approve_status.success?, approve_stderr
      assert_equal approved, JSON.parse(File.read(approved_path))

      status, status_stderr, status_result = command_json('plan', 'status', approved_path)
      assert status_result.success?, status_stderr
      assert_equal true, status.fetch('valid')
      assert_equal approved.fetch('approved_plan_id'), status.fetch('approved_plan_id')
      assert_equal 'approved', status.fetch('status')

      result, apply_stderr, apply_status = command_json(
        'plan',
        'apply',
        approved_path,
        '--confirm',
        "--journal-dir=#{journal_dir}"
      )
      assert apply_status.success?, apply_stderr
      assert_equal 'succeeded', result.dig('execution', 'result', 'status')
      assert_equal approved.fetch('approved_plan_id'),
                   result.dig('execution', 'approved_plan', 'approved_plan_id')

      managed_manifest = File.join(
        managed_dir,
        'checkout-api',
        'prometheus_stack',
        'manifest.json'
      )
      assert File.exist?(managed_manifest)
      assert_equal approved.dig('provider_plan', 'desired_state', 'resources'),
                   JSON.parse(File.read(managed_manifest))

      journal_path = result.dig('execution', 'operation_journal', 'path')
      journal = JSON.parse(File.read(journal_path))
      assert_equal approved.fetch('approved_plan_id'),
                   journal.dig('plan', 'approved_plan', 'approved_plan_id')
      assert_equal approved.dig('provider_plan', 'fingerprint'),
                   journal.dig('plan', 'approved_plan', 'provider_plan_fingerprint')
      assert_equal approved.dig('source_bundle', 'bundle_id'),
                   journal.dig('plan', 'approved_plan', 'source_bundle_id')
    end
  end

  def test_approval_is_idempotent_and_refuses_conflicting_output
    Dir.mktmpdir do |dir|
      fixture, bundle_path, = write_planned_bundle(dir)
      approved_path = File.join(dir, 'approved-plan.json')
      args = [
        'plan',
        'approve',
        bundle_path,
        "--target=#{fixture.fetch(:target)}",
        "--reviewer=#{REVIEWER}",
        "--reviewed-at=#{REVIEWED_AT}",
        "--output=#{approved_path}"
      ]

      first, first_stderr, first_status = command_json(*args)
      second, second_stderr, second_status = command_json(*args)
      assert first_status.success?, first_stderr
      assert second_status.success?, second_stderr
      assert_equal first, second

      conflict, _stderr, conflict_status = command_json(
        *args,
        '--note=Different approval content.'
      )
      refute conflict_status.success?
      assert_equal 'approved_plan_output_conflict', conflict.dig('error', 'code')
      assert_equal first, JSON.parse(File.read(approved_path))
    end
  end

  def test_apply_rejects_managed_state_drift_before_journal_or_mutation
    Dir.mktmpdir do |dir|
      fixture, bundle_path, managed_dir = write_planned_bundle(dir)
      approved_path = File.join(dir, 'approved-plan.json')
      journal_dir = File.join(dir, 'journals')
      approved, stderr, status = approve(fixture, bundle_path, approved_path)
      assert status.success?, stderr

      manifest_path = approved.fetch('provider_plan')
                              .fetch('changes')
                              .find { |change| change.fetch('target') == 'manifest_file' }
                              .fetch('desired')
                              .fetch('path')
      FileUtils.mkdir_p(File.dirname(manifest_path))
      drift = JSON.pretty_generate('unreviewed' => 'managed-state change')
      File.write(manifest_path, drift)

      result, apply_stderr, apply_status = command_json(
        'plan',
        'apply',
        approved_path,
        '--confirm',
        "--journal-dir=#{journal_dir}"
      )

      refute apply_status.success?, apply_stderr
      assert_equal 'stale_approved_plan', result.dig('error', 'code')
      assert_equal approved.fetch('approved_plan_id'), result.fetch('approved_plan_id')
      assert_equal drift, File.read(manifest_path)
      assert_empty Dir.glob(File.join(journal_dir, '**', '*.json'))
      assert File.exist?(managed_dir)
    end
  end

  def test_apply_rejects_a_concurrent_exact_apply_for_the_same_managed_scope
    Dir.mktmpdir do |dir|
      fixture, bundle_path, managed_dir = write_planned_bundle(dir)
      approved_path = File.join(dir, 'approved-plan.json')
      journal_dir = File.join(dir, 'journals')
      approved, stderr, status = approve(fixture, bundle_path, approved_path)
      assert status.success?, stderr
      document = SloRulesEngine::ProviderState::ApprovedPlan::Loader.new.load(approved)
      executor = SloRulesEngine::ProviderState::ExactPlanExecutor.new(journal_dir: journal_dir)
      lock_path = executor.scope_lock_path(document)
      FileUtils.mkdir_p(File.dirname(lock_path))

      File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
        assert lock.flock(File::LOCK_EX | File::LOCK_NB)
        result, apply_stderr, apply_status = command_json(
          'plan',
          'apply',
          approved_path,
          '--confirm',
          "--journal-dir=#{journal_dir}"
        )

        refute apply_status.success?, apply_stderr
        assert_equal 'approved_plan_scope_busy', result.dig('error', 'code')
        refute File.exist?(
          File.join(managed_dir, 'checkout-api', 'prometheus_stack', 'manifest.json')
        )
        assert_empty Dir.glob(File.join(journal_dir, '**', '*.json'))
      end
    end
  end

  def test_apply_uses_locked_manifest_after_original_bundle_source_changes
    Dir.mktmpdir do |dir|
      fixture, bundle_path, managed_dir = write_planned_bundle(dir)
      approved_path = File.join(dir, 'approved-plan.json')
      journal_dir = File.join(dir, 'journals')
      approved, stderr, status = approve(fixture, bundle_path, approved_path)
      assert status.success?, stderr
      File.write(fixture.fetch(:manifest), JSON.pretty_generate('changed' => 'after approval'))

      result, apply_stderr, apply_status = command_json(
        'plan',
        'apply',
        approved_path,
        '--confirm',
        "--journal-dir=#{journal_dir}"
      )

      assert apply_status.success?, apply_stderr
      assert_equal 'succeeded', result.dig('execution', 'result', 'status')
      managed_manifest = File.join(
        managed_dir,
        'checkout-api',
        'prometheus_stack',
        'manifest.json'
      )
      assert_equal approved.dig('provider_plan', 'desired_state', 'resources'),
                   JSON.parse(File.read(managed_manifest))
    end
  end

  def test_exact_sloth_apply_writes_native_input_and_preserves_pending_handoff
    Dir.mktmpdir do |dir|
      fixture, bundle_path, managed_dir = write_planned_bundle(dir, provider: 'sloth')
      approved_path = File.join(dir, 'approved-sloth-plan.json')
      journal_dir = File.join(dir, 'journals')
      _approved, stderr, status = approve(fixture, bundle_path, approved_path)
      assert status.success?, stderr

      result, apply_stderr, apply_status = command_json(
        'plan',
        'apply',
        approved_path,
        '--confirm',
        "--journal-dir=#{journal_dir}"
      )

      assert apply_status.success?, apply_stderr
      assert File.exist?(
        File.join(managed_dir, 'checkout-api', 'sloth', 'generated', 'sloth.yaml')
      )
      assert_equal 'succeeded', result.dig('execution', 'result', 'verification', 'engine_owned_status')
      assert_equal 'pending', result.dig('execution', 'result', 'verification', 'external_status')
      handoff = result.dig('execution', 'result', 'operation_results').find do |operation|
        operation.fetch('target') == 'external_generator'
      end
      assert_equal 'skipped', handoff.fetch('status')
    end
  end

  def test_completed_exact_plan_replay_rechecks_state_without_rewriting_files
    Dir.mktmpdir do |dir|
      fixture, bundle_path, managed_dir = write_planned_bundle(dir)
      approved_path = File.join(dir, 'approved-plan.json')
      journal_dir = File.join(dir, 'journals')
      _approved, stderr, status = approve(fixture, bundle_path, approved_path)
      assert status.success?, stderr
      first, first_stderr, first_status = command_json(
        'plan',
        'apply',
        approved_path,
        '--confirm',
        "--journal-dir=#{journal_dir}"
      )
      assert first_status.success?, first_stderr
      manifest_path = File.join(
        managed_dir,
        'checkout-api',
        'prometheus_stack',
        'manifest.json'
      )
      first_mtime = File.stat(manifest_path).mtime
      journal_path = first.dig('execution', 'operation_journal', 'path')
      journal_bytes = File.binread(journal_path)

      second, second_stderr, second_status = command_json(
        'plan',
        'apply',
        approved_path,
        '--confirm',
        "--journal-dir=#{journal_dir}"
      )

      assert second_status.success?, second_stderr
      assert_equal 'completed', second.dig('execution', 'replay', 'status')
      assert_equal false, second.dig('execution', 'replay', 'mutated')
      assert_equal true, second.dig('execution', 'replay', 'state_rechecked')
      assert_equal journal_path, second.dig('execution', 'operation_journal', 'path')
      assert_equal first_mtime, File.stat(manifest_path).mtime
      assert_equal journal_bytes, File.binread(journal_path)
      assert_equal 1, Dir.glob(File.join(journal_dir, '**', '*.json')).length

      File.write(manifest_path, JSON.pretty_generate('drift' => 'after completion'))
      stale, stale_stderr, stale_status = command_json(
        'plan',
        'apply',
        approved_path,
        '--confirm',
        "--journal-dir=#{journal_dir}"
      )
      refute stale_status.success?, stale_stderr
      assert_equal 'stale_approved_plan', stale.dig('error', 'code')
      assert_equal journal_bytes, File.binread(journal_path)
    end
  end

  def test_partial_exact_plan_requires_explicit_resume_and_emits_rollback_guidance
    Dir.mktmpdir do |dir|
      fixture, bundle_path, managed_dir = write_planned_bundle(dir)
      approved_path = File.join(dir, 'approved-plan.json')
      journal_dir = File.join(dir, 'journals')
      _approved, stderr, status = approve(fixture, bundle_path, approved_path)
      assert status.success?, stderr
      generated_path = File.join(
        managed_dir,
        'checkout-api',
        'prometheus_stack',
        'generated'
      )
      FileUtils.mkdir_p(File.dirname(generated_path))
      File.write(generated_path, 'blocks generated directory creation')

      first, _first_stderr, first_status = command_json(
        'plan',
        'apply',
        approved_path,
        '--confirm',
        "--journal-dir=#{journal_dir}"
      )
      refute first_status.success?
      assert_equal 'partial', first.dig('execution', 'result', 'status')
      assert_equal false, first.dig('execution', 'rollback', 'supported')
      assert_equal true, first.dig('execution', 'rollback', 'requires_state_recheck')
      journal_path = first.dig('execution', 'operation_journal', 'path')
      journal_bytes = File.binread(journal_path)

      second, second_stderr, second_status = command_json(
        'plan',
        'apply',
        approved_path,
        '--confirm',
        "--journal-dir=#{journal_dir}"
      )

      refute second_status.success?, second_stderr
      assert_equal 'approved_plan_requires_resume', second.dig('error', 'code')
      assert_equal journal_path, second.dig('findings', 0, 'journal_path')
      assert_equal journal_bytes, File.binread(journal_path)
    end
  end

  private

  def write_planned_bundle(dir, provider: 'prometheus_stack')
    fixture = write_release_bundle_fixture(dir, provider: provider)
    review_ready = SloRulesEngine::ReleaseBundle::Builder.new.build(
      fixture.fetch(:artifact_index),
      reviewer: REVIEWER,
      reviewed_at: REVIEWED_AT
    )
    managed_dir = File.join(dir, 'managed')
    apply_ready = SloRulesEngine::ReleaseBundle::Planner.new.plan(
      review_ready,
      target_runtime: {
        fixture.fetch(:target) => {
          output_dir: managed_dir
        }
      }
    )
    path = File.join(dir, 'apply-ready.json')
    File.write(path, JSON.pretty_generate(apply_ready))
    [fixture, path, managed_dir]
  end

  def approve(fixture, bundle_path, approved_path)
    command_json(
      'plan',
      'approve',
      bundle_path,
      "--target=#{fixture.fetch(:target)}",
      "--reviewer=#{REVIEWER}",
      "--reviewed-at=#{REVIEWED_AT}",
      "--output=#{approved_path}"
    )
  end

  def command_json(*argv)
    stdout, stderr, status = Open3.capture3('ruby', File.join(ROOT, 'bin', 'rules-ctl'), *argv)
    [JSON.parse(stdout), stderr, status]
  end
end
