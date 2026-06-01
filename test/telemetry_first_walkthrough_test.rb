# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'open3'
require 'fileutils'
require 'tmpdir'

class TelemetryFirstWalkthroughTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def test_saved_artifact_walkthrough_reaches_reviewed_provider_gate
    fixture_dir = File.join(ROOT, 'examples', 'onboarding', 'telemetry-first')
    discovery_index = File.join(fixture_dir, 'discovery', 'index.json')
    reviewed_definition = File.join(fixture_dir, 'reviewed-definition.rb')

    Dir.mktmpdir do |dir|
      handoff_dir = File.join(dir, 'handoff')
      draft_dir = File.join(dir, 'drafts')
      generated_dir = File.join(dir, 'generated')
      FileUtils.mkdir_p(draft_dir)

      summary = json_command(
        'onboarding-summary',
        "--handoff-dir=#{handoff_dir}",
        discovery_index
      )
      assert_equal 'ready', summary.fetch('scopes').fetch(0).fetch('readiness')

      handoff_path = File.join(handoff_dir, 'checkout-prod.handoff.json')
      review = json_command(
        'review-handoff',
        '--accept=request-latency',
        '--reject=request-traffic',
        '--note=Latency accepted for the walkthrough.',
        handoff_path
      )
      assert_equal 'reviewed', review.fetch('review').fetch('status')

      validation = json_command('validate-handoff', handoff_path)
      assert_equal true, validation.fetch('valid')

      draft = command(
        'draft-from-handoff',
        '--service=checkout-api',
        '--owner=payments-platform',
        handoff_path
      )
      draft_path = File.join(draft_dir, 'checkout-prod.rb')
      File.write(draft_path, draft)
      draft_validation = json_command('validate', draft_path)
      assert_equal true, draft_validation.fetch(0).fetch('valid')

      generated = json_command(
        'generate',
        '--provider=datadog',
        "--output-dir=#{generated_dir}",
        "--handoff-dir=#{handoff_dir}",
        reviewed_definition
      )
      assert_equal 'checkout-api', generated.fetch(0).fetch('service')

      manifest_path = File.join(generated_dir, 'checkout-api', 'datadog', 'manifest.json')
      report_path = File.join(generated_dir, 'manifest-review', 'datadog.json')
      report = json_command(
        'manifest-review',
        '--provider=datadog',
        "--manifest=#{manifest_path}",
        "--handoff-dir=#{handoff_dir}",
        "--report=#{report_path}"
      )
      assert_equal true, report.fetch('saved_report').fetch('fresh')

      artifact_index_path = File.join(dir, 'artifact-index.json')
      artifact_index = json_command(
        'onboarding-artifact-index',
        "--handoff-dir=#{handoff_dir}",
        "--draft-dir=#{draft_dir}",
        "--manifest-dir=#{generated_dir}",
        '--provider=datadog',
        "--output=#{artifact_index_path}",
        discovery_index
      )
      assert_equal 1, artifact_index.fetch('summary').fetch('complete_scopes')
      assert_equal 0, artifact_index.fetch('summary').fetch('missing_artifact_count')
      assert_equal artifact_index, JSON.parse(File.read(artifact_index_path))

      gated = json_command(
        { 'DD_API_KEY' => nil, 'DD_APP_KEY' => nil },
        'apply',
        '--provider=datadog',
        '--confirm',
        "--manifest=#{manifest_path}",
        "--handoff-dir=#{handoff_dir}",
        "--review-report=#{report_path}",
        expect_success: false
      )
      assert_equal 'missing_credentials', gated.fetch('error').fetch('code')
    end
  end

  private

  def json_command(*argv, expect_success: true)
    JSON.parse(command(*argv, expect_success: expect_success))
  end

  def command(*argv, expect_success: true)
    env = argv.first.is_a?(Hash) ? argv.shift : {}
    stdout, stderr, status = Open3.capture3(env, 'ruby', File.join(ROOT, 'bin', 'rules-ctl'), *argv)
    assert_equal expect_success, status.success?, stderr.empty? ? stdout : stderr
    stdout
  end
end
