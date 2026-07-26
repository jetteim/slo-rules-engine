# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require_relative 'support/release_bundle_fixtures'

class ReleaseBundleCliTest < Minitest::Test
  include ReleaseBundleFixtures

  ROOT = File.expand_path('..', __dir__)
  REVIEWER = 'team/payments-sre'
  REVIEWED_AT = '2026-07-26T09:30:00Z'

  def test_bundle_create_writes_review_ready_bundle_with_stable_identity
    Dir.mktmpdir do |dir|
      fixture = write_release_bundle_fixture(dir)
      first_path = File.join(dir, 'release-bundle.json')
      second_path = File.join(dir, 'release-bundle-copy.json')

      first, first_status = bundle_create(fixture, first_path)
      second, second_status = bundle_create(fixture, second_path)

      assert first_status.success?
      assert second_status.success?
      assert_equal 'review_ready', first.fetch('lifecycle')
      assert_equal first.fetch('bundle_id'), second.fetch('bundle_id')
      assert_equal first, JSON.parse(File.read(first_path))
      assert_equal second, JSON.parse(File.read(second_path))
    end
  end

  def test_bundle_create_with_plan_writes_apply_ready_bundle_and_status_is_clean
    Dir.mktmpdir do |dir|
      fixture = write_release_bundle_fixture(dir, include_plan: true)
      bundle_path = File.join(dir, 'release-bundle.json')

      bundle, create_status = bundle_create(fixture, bundle_path, include_plan: true)
      status, stderr, status_result = command('bundle', 'status', bundle_path)

      assert create_status.success?
      assert status_result.success?, stderr
      assert_equal 'apply_ready', bundle.fetch('lifecycle')
      assert_equal true, status.fetch('valid')
      assert_equal 'apply_ready', status.fetch('effective_lifecycle')
      assert_equal 0, status.fetch('summary').fetch('stale_sources')
    end
  end

  def test_bundle_status_fails_when_a_source_artifact_changes
    Dir.mktmpdir do |dir|
      fixture = write_release_bundle_fixture(dir)
      bundle_path = File.join(dir, 'release-bundle.json')
      _bundle, create_status = bundle_create(fixture, bundle_path)
      assert create_status.success?
      File.write(fixture.fetch(:draft), "# changed after bundling\n")

      status, _stderr, result = command('bundle', 'status', bundle_path)

      refute result.success?
      assert_equal false, status.fetch('valid')
      assert_equal 'stale', status.fetch('effective_lifecycle')
      assert_equal ['source_artifact_changed'], status.fetch('findings').map { |finding| finding.fetch('code') }
    end
  end

  def test_bundle_create_rejects_stale_predecessors_without_writing_output
    Dir.mktmpdir do |dir|
      fixture = write_release_bundle_fixture(dir)
      manifest = JSON.parse(File.read(fixture.fetch(:manifest)))
      manifest.fetch('review_provenance')['notes'] = ['Changed after report creation.']
      File.write(fixture.fetch(:manifest), JSON.pretty_generate(manifest))
      bundle_path = File.join(dir, 'release-bundle.json')

      payload, _stderr, result = command(
        'bundle',
        'create',
        "--artifact-index=#{fixture.fetch(:artifact_index)}",
        "--reviewer=#{REVIEWER}",
        "--reviewed-at=#{REVIEWED_AT}",
        "--output=#{bundle_path}"
      )

      refute result.success?
      assert_equal false, payload.fetch('valid')
      assert_equal 'stale_bundle_inputs', payload.fetch('error').fetch('code')
      refute File.exist?(bundle_path)
    end
  end

  def test_bundle_create_rejects_credential_keys_without_writing_output
    Dir.mktmpdir do |dir|
      fixture = write_release_bundle_fixture(dir, include_plan: true)
      plan = JSON.parse(File.read(fixture.fetch(:plan)))
      plan['token'] = 'must-not-be-packaged'
      File.write(fixture.fetch(:plan), JSON.pretty_generate(plan))
      bundle_path = File.join(dir, 'release-bundle.json')

      payload, _stderr, result = command(
        'bundle',
        'create',
        "--artifact-index=#{fixture.fetch(:artifact_index)}",
        "--reviewer=#{REVIEWER}",
        "--reviewed-at=#{REVIEWED_AT}",
        "--plan=#{fixture.fetch(:target)}=#{fixture.fetch(:plan)}",
        "--output=#{bundle_path}"
      )

      refute result.success?
      assert_equal false, payload.fetch('valid')
      assert_equal 'credential_material_forbidden', payload.fetch('error').fetch('code')
      assert_equal ['artifacts.change_plan.content.token'], payload.fetch('errors').map { |error| error.fetch('path') }
      refute File.exist?(bundle_path)
    end
  end

  private

  def bundle_create(fixture, output_path, include_plan: false)
    argv = [
      'bundle',
      'create',
      "--artifact-index=#{fixture.fetch(:artifact_index)}",
      "--reviewer=#{REVIEWER}",
      "--reviewed-at=#{REVIEWED_AT}",
      "--output=#{output_path}"
    ]
    argv << "--plan=#{fixture.fetch(:target)}=#{fixture.fetch(:plan)}" if include_plan
    payload, stderr, status = command(*argv)
    assert status.success?, stderr
    [payload, status]
  end

  def command(*argv)
    stdout, stderr, status = Open3.capture3('ruby', File.join(ROOT, 'bin', 'rules-ctl'), *argv)
    [JSON.parse(stdout), stderr, status]
  end
end
