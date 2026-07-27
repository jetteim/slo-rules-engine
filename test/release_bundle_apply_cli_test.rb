# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require_relative 'support/release_bundle_fixtures'

class ReleaseBundleApplyCliTest < Minitest::Test
  include ReleaseBundleFixtures

  ROOT = File.expand_path('..', __dir__)
  REVIEWER = 'team/payments-sre'
  REVIEWED_AT = '2026-07-27T09:30:00Z'

  def test_bundle_apply_executes_two_approved_targets_and_replays_idempotently
    Dir.mktmpdir do |dir|
      fixture, bundle_path, bundle, approval_paths, managed_dir = write_inputs(dir)
      journal_dir = File.join(dir, 'journals')
      output_path = File.join(dir, 'applied.json')
      predecessor_bytes = File.binread(bundle_path)

      applied, stderr, status = command_json(
        'bundle',
        'apply',
        bundle_path,
        '--confirm',
        "--approved-plan=#{approval_paths.fetch('checkout-api/prometheus_stack')}",
        "--approved-plan=#{approval_paths.fetch('checkout-api/sloth')}",
        "--journal-dir=#{journal_dir}",
        "--output=#{output_path}"
      )

      assert status.success?, stderr
      assert_equal 'applied', applied.fetch('lifecycle')
      assert_equal bundle.fetch(:bundle_id), applied.dig('transition', 'predecessor_bundle_id')
      assert_equal 2, applied.dig('summary', 'execution_count')
      assert_equal({ 'succeeded' => 2 }, applied.dig('summary', 'executions_by_status'))
      assert_equal predecessor_bytes, File.binread(bundle_path)
      assert File.exist?(File.join(managed_dir, 'checkout-api', 'prometheus_stack', 'manifest.json'))
      assert File.exist?(File.join(managed_dir, 'checkout-api', 'sloth', 'manifest.json'))
      assert Dir.glob(File.join(managed_dir, 'checkout-api', 'sloth', 'generated', '*.yaml')).any?
      first_bytes = File.binread(output_path)
      managed_mtimes = managed_files(managed_dir).to_h { |path| [path, File.mtime(path)] }

      replayed, replay_stderr, replay_status = command_json(
        'bundle',
        'apply',
        bundle_path,
        '--confirm',
        "--approved-plan=#{approval_paths.fetch('checkout-api/sloth')}",
        "--approved-plan=#{approval_paths.fetch('checkout-api/prometheus_stack')}",
        "--journal-dir=#{journal_dir}",
        "--output=#{output_path}"
      )

      assert replay_status.success?, replay_stderr
      assert_equal applied.fetch('bundle_id'), replayed.fetch('bundle_id')
      assert_equal first_bytes, File.binread(output_path)
      assert_equal managed_mtimes, managed_files(managed_dir).to_h { |path| [path, File.mtime(path)] }
      assert_equal fixture.fetch(:targets).sort,
                   replayed.fetch('targets').map { |target| target.fetch('uid') }.sort
    end
  end

  def test_bundle_apply_rejects_missing_target_approval_before_writes
    Dir.mktmpdir do |dir|
      _fixture, bundle_path, _bundle, approval_paths, managed_dir = write_inputs(dir)
      journal_dir = File.join(dir, 'journals')
      output_path = File.join(dir, 'applied.json')

      payload, _stderr, status = command_json(
        'bundle',
        'apply',
        bundle_path,
        '--confirm',
        "--approved-plan=#{approval_paths.fetch('checkout-api/prometheus_stack')}",
        "--journal-dir=#{journal_dir}",
        "--output=#{output_path}"
      )

      refute status.success?
      assert_equal 'incomplete_approved_plan_coverage', payload.dig('error', 'code')
      refute File.exist?(managed_dir)
      refute File.exist?(journal_dir)
      refute File.exist?(output_path)
    end
  end

  def test_bundle_apply_rejects_incompatible_existing_output_before_writes
    Dir.mktmpdir do |dir|
      _fixture, bundle_path, _bundle, approval_paths, managed_dir = write_inputs(dir)
      journal_dir = File.join(dir, 'journals')
      output_path = File.join(dir, 'applied.json')
      File.write(output_path, JSON.pretty_generate({ 'unrelated' => true }))
      output_bytes = File.binread(output_path)

      payload, _stderr, status = command_json(
        'bundle',
        'apply',
        bundle_path,
        '--confirm',
        *approval_paths.values.map { |path| "--approved-plan=#{path}" },
        "--journal-dir=#{journal_dir}",
        "--output=#{output_path}"
      )

      refute status.success?
      assert_equal 'release_bundle_output_conflict', payload.dig('error', 'code')
      assert_equal output_bytes, File.binread(output_path)
      refute File.exist?(managed_dir)
      refute File.exist?(journal_dir)
    end
  end

  def test_bundle_apply_stops_on_partial_target_until_that_plan_is_explicitly_resumed
    Dir.mktmpdir do |dir|
      _fixture, bundle_path, _bundle, approval_paths, managed_dir = write_inputs(dir)
      journal_dir = File.join(dir, 'journals')
      output_path = File.join(dir, 'applied.json')
      sloth_root = File.join(managed_dir, 'checkout-api', 'sloth')
      FileUtils.mkdir_p(sloth_root)
      blocker = File.join(sloth_root, 'generated')
      File.write(blocker, 'blocks the approved input directory')

      payload, _stderr, status = command_json(
        'bundle',
        'apply',
        bundle_path,
        '--confirm',
        *approval_paths.values.map { |path| "--approved-plan=#{path}" },
        "--journal-dir=#{journal_dir}",
        "--output=#{output_path}"
      )

      refute status.success?
      assert_equal 'bundle_target_execution_incomplete', payload.dig('error', 'code')
      assert_equal 'checkout-api/sloth', payload.fetch('target_uid')
      assert_equal ['checkout-api/prometheus_stack'],
                   payload.fetch('completed_targets').map { |target| target.fetch('target_uid') }
      assert File.exist?(File.join(managed_dir, 'checkout-api', 'prometheus_stack', 'manifest.json'))
      refute File.exist?(output_path)

      File.delete(blocker)
      resumed, resume_stderr, resume_status = command_json(
        'plan',
        'resume',
        approval_paths.fetch('checkout-api/sloth'),
        '--confirm',
        "--journal-dir=#{journal_dir}"
      )
      assert resume_status.success?, [resume_stderr, resumed].inspect
      assert_includes %w[succeeded noop], resumed.dig('execution', 'result', 'status')

      applied, apply_stderr, apply_status = command_json(
        'bundle',
        'apply',
        bundle_path,
        '--confirm',
        *approval_paths.values.reverse.map { |path| "--approved-plan=#{path}" },
        "--journal-dir=#{journal_dir}",
        "--output=#{output_path}"
      )
      assert apply_status.success?, apply_stderr
      assert_equal 'applied', applied.fetch('lifecycle')
      assert File.exist?(File.join(sloth_root, 'generated', 'sloth.yaml'))
    end
  end

  private

  def write_inputs(dir)
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
    runtime = fixture.fetch(:targets).to_h do |target_uid|
      [target_uid, { output_dir: managed_dir }]
    end
    bundle = SloRulesEngine::ReleaseBundle::Planner.new.plan(
      review_ready,
      target_runtime: runtime
    )
    bundle_path = File.join(dir, 'apply-ready.json')
    File.write(bundle_path, JSON.pretty_generate(bundle))
    approval_paths = fixture.fetch(:targets).to_h do |target_uid|
      payload = SloRulesEngine::ProviderState::ApprovedPlan::Builder.new.build(
        bundle,
        target_uid: target_uid,
        reviewer: REVIEWER,
        reviewed_at: REVIEWED_AT
      )
      path = File.join(dir, "#{target_uid.tr('/', '-')}.approved.json")
      SloRulesEngine::ProviderState::ApprovedPlan::Store.new.write(path, payload)
      [target_uid, path]
    end
    [fixture, bundle_path, bundle, approval_paths, managed_dir]
  end

  def managed_files(managed_dir)
    Dir.glob(File.join(managed_dir, '**', '*')).select { |path| File.file?(path) }.sort
  end

  def command_json(*argv)
    stdout, stderr, status = Open3.capture3('ruby', File.join(ROOT, 'bin', 'rules-ctl'), *argv)
    [JSON.parse(stdout), stderr, status]
  end
end
