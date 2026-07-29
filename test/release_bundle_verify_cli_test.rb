# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require_relative 'support/release_bundle_fixtures'

class ReleaseBundleVerifyCliTest < Minitest::Test
  include ReleaseBundleFixtures

  ROOT = File.expand_path('..', __dir__)
  REVIEWER = 'team/payments-sre'
  REVIEWED_AT = '2026-07-27T09:30:00Z'

  def test_bundle_verify_writes_a_verified_successor_without_rewriting_managed_files
    Dir.mktmpdir do |dir|
      applied_path, applied, managed_dir = write_applied_input(dir)
      output_path = File.join(dir, 'verified.json')
      predecessor_bytes = File.binread(applied_path)
      managed_mtimes = managed_files(managed_dir).to_h { |path| [path, File.mtime(path)] }

      verified, stderr, status = command_json(
        'bundle',
        'verify',
        applied_path,
        "--output=#{output_path}"
      )

      assert status.success?, stderr
      assert_equal 'verified', verified.fetch('lifecycle')
      assert_equal applied.fetch(:bundle_id), verified.dig('transition', 'predecessor_bundle_id')
      assert_equal 2, verified.dig('summary', 'verification_count')
      assert_equal verified, JSON.parse(File.read(output_path))
      assert_equal predecessor_bytes, File.binread(applied_path)
      assert_equal managed_mtimes, managed_files(managed_dir).to_h { |path| [path, File.mtime(path)] }
      first_bytes = File.binread(output_path)

      replayed, replay_stderr, replay_status = command_json(
        'bundle',
        'verify',
        applied_path,
        "--output=#{output_path}"
      )

      assert replay_status.success?, replay_stderr
      assert_equal verified.fetch('bundle_id'), replayed.fetch('bundle_id')
      assert_equal first_bytes, File.binread(output_path)
      assert_equal managed_mtimes, managed_files(managed_dir).to_h { |path| [path, File.mtime(path)] }
    end
  end

  def test_bundle_verify_reports_drift_and_does_not_write_a_successor
    Dir.mktmpdir do |dir|
      applied_path, _applied, managed_dir = write_applied_input(dir)
      output_path = File.join(dir, 'verified.json')
      path = File.join(managed_dir, 'checkout-api', 'prometheus_stack', 'manifest.json')
      File.write(path, "{}\n")

      payload, _stderr, status = command_json(
        'bundle',
        'verify',
        applied_path,
        "--output=#{output_path}"
      )

      refute status.success?
      assert_equal 'bundle_target_verification_failed', payload.dig('error', 'code')
      assert_equal 'checkout-api/prometheus_stack', payload.fetch('target_uid')
      refute File.exist?(output_path)
    end
  end

  def test_bundle_verify_rejects_an_incompatible_output_before_managed_file_reads
    Dir.mktmpdir do |dir|
      applied_path, _applied, managed_dir = write_applied_input(dir)
      output_path = File.join(dir, 'verified.json')
      File.write(output_path, JSON.pretty_generate({ unrelated: true }))
      output_bytes = File.binread(output_path)
      File.delete(File.join(managed_dir, 'checkout-api', 'prometheus_stack', 'manifest.json'))

      payload, _stderr, status = command_json(
        'bundle',
        'verify',
        applied_path,
        "--output=#{output_path}"
      )

      refute status.success?
      assert_equal 'release_bundle_output_conflict', payload.dig('error', 'code')
      assert_equal output_bytes, File.binread(output_path)
    end
  end

  def test_bundle_verify_rejects_in_place_output
    Dir.mktmpdir do |dir|
      applied_path, = write_applied_input(dir)

      payload, _stderr, status = command_json(
        'bundle',
        'verify',
        applied_path,
        "--output=#{applied_path}"
      )

      refute status.success?
      assert_equal 'immutable_bundle_input', payload.dig('error', 'code')
    end
  end

  private

  def write_applied_input(dir)
    fixture = write_release_bundle_fixture(
      dir,
      providers: %w[prometheus_stack sloth]
    )
    review_ready = SloRulesEngine::ReleaseBundle::Builder.new.build(
      fixture.fetch(:artifact_index),
      reviewer: REVIEWER,
      reviewed_at: REVIEWED_AT
    )
    managed_dir = File.join(dir, 'managed')
    apply_ready = SloRulesEngine::ReleaseBundle::Planner.new.plan(
      review_ready,
      target_runtime: fixture.fetch(:targets).to_h do |target_uid|
        [target_uid, { output_dir: managed_dir }]
      end
    )
    documents = fixture.fetch(:targets).map do |target_uid|
      SloRulesEngine::ProviderState::ApprovedPlan::Loader.new.load(
        SloRulesEngine::ProviderState::ApprovedPlan::Builder.new.build(
          apply_ready,
          target_uid: target_uid,
          reviewer: REVIEWER,
          reviewed_at: REVIEWED_AT
        )
      )
    end
    applied = SloRulesEngine::ReleaseBundle::Applier.new(
      executor: SloRulesEngine::ProviderState::ExactPlanExecutor.new(
        journal_dir: File.join(dir, 'journals')
      )
    ).apply(apply_ready, approved_plans: documents)
    path = File.join(dir, 'applied.json')
    File.write(path, JSON.pretty_generate(applied))
    [path, applied, managed_dir]
  end

  def managed_files(root)
    Dir.glob(File.join(root, '**', '*')).select { |path| File.file?(path) }.sort
  end

  def command_json(*argv)
    stdout, stderr, status = Open3.capture3('ruby', File.join(ROOT, 'bin', 'rules-ctl'), *argv)
    [JSON.parse(stdout), stderr, status]
  end
end
