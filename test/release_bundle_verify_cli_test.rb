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

  def test_bundle_verify_packages_sloth_evidence_and_live_downstream_status
    Dir.mktmpdir do |dir|
      applied_path, _applied, managed_dir, fixture = write_applied_input(dir)
      evidence = write_sloth_downstream_evidence_fixture(
        dir,
        fixture.fetch(:manifests).fetch('sloth')
      )
      output_path = File.join(dir, 'verified-downstream.json')
      request_log_path = File.join(dir, 'requests.log')
      fake_http = File.join(dir, 'fake_prometheus_status_http.rb')
      FileUtils.cp(File.expand_path('support/fake_prometheus_status_http.rb', __dir__), fake_http)
      managed_mtimes = managed_files(managed_dir).to_h { |path| [path, File.mtime(path)] }

      verified, stderr, status = command_json(
        'bundle',
        'verify',
        applied_path,
        "--sloth-evidence=checkout-api/sloth=#{evidence.fetch(:evidence)}",
        '--target-base-url=checkout-api/sloth=http://sloth-prometheus.example.test',
        '--max-age-seconds=300',
        "--output=#{output_path}",
        env: {
          'RUBYOPT' => "-r#{fake_http}",
          'PROMETHEUS_REQUEST_LOG' => request_log_path
        }
      )

      assert status.success?, stderr
      assert_equal verified, JSON.parse(File.read(output_path))
      sloth_target = verified.fetch('targets').find { |target| target.fetch('provider') == 'sloth' }
      sloth_verification = verified.fetch('artifacts').find do |artifact|
        artifact.fetch('uid') == sloth_target.fetch('verification_artifact_uid')
      end.fetch('content')
      assert_equal 'succeeded', sloth_verification.dig('verification', 'external_status')
      assert_equal 'healthy', sloth_verification.dig('verification', 'resources', -1, 'live_status_report', 'statuses', 0, 'state')
      assert_equal 8, File.readlines(request_log_path).length
      assert_equal managed_mtimes, managed_files(managed_dir).to_h { |path| [path, File.mtime(path)] }
      refute_includes JSON.generate(verified), 'sloth-prometheus.example.test'
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
    [path, applied, managed_dir, fixture]
  end

  def managed_files(root)
    Dir.glob(File.join(root, '**', '*')).select { |path| File.file?(path) }.sort
  end

  def command_json(*argv, env: {})
    stdout, stderr, status = Open3.capture3(env, 'ruby', File.join(ROOT, 'bin', 'rules-ctl'), *argv)
    [JSON.parse(stdout), stderr, status]
  end
end
