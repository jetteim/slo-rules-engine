# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'open3'
require 'tempfile'
require 'tmpdir'

class DatadogExecutionCliTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def test_confirmed_datadog_apply_requires_journal_directory_before_credentials
    with_reviewed_manifest do |manifest_path|
      _stdout, stderr, status = command(
        { 'DD_API_KEY' => nil, 'DD_APP_KEY' => nil },
        'apply',
        '--provider=datadog',
        '--confirm',
        "--manifest=#{manifest_path}"
      )

      refute status.success?
      assert_includes stderr, 'live Datadog apply requires --journal-dir'
    end
  end

  def test_confirmed_datadog_apply_checks_credentials_before_creating_journal
    with_reviewed_manifest do |manifest_path|
      Dir.mktmpdir do |dir|
        stdout, stderr, status = command(
          { 'DD_API_KEY' => nil, 'DD_APP_KEY' => nil },
          'apply',
          '--provider=datadog',
          '--confirm',
          "--journal-dir=#{dir}",
          "--manifest=#{manifest_path}"
        )

        refute status.success?, stderr
        assert_equal 'missing_credentials', JSON.parse(stdout).dig('error', 'code')
        assert_empty Dir.glob(File.join(dir, '**', '*.json'))
      end
    end
  end

  def test_confirmed_datadog_prune_requires_journal_directory
    with_reviewed_manifest do |manifest_path|
      _stdout, stderr, status = command(
        { 'DD_API_KEY' => nil, 'DD_APP_KEY' => nil },
        'prune',
        '--provider=datadog',
        '--confirm',
        "--manifest=#{manifest_path}"
      )

      refute status.success?
      assert_includes stderr, 'live Datadog prune requires --journal-dir'
    end
  end

  private

  def with_reviewed_manifest
    stdout, stderr, status = command(
      {},
      'generate',
      '--provider=datadog',
      File.join(ROOT, 'examples', 'services', 'checkout.rb')
    )
    assert status.success?, stderr
    manifest = JSON.parse(stdout).fetch(0)
    manifest['review_provenance'] = {
      'label' => 'checkout-prod',
      'provider' => 'datadog',
      'accepted_candidate_uids' => ['request-latency'],
      'notes' => ['Reviewed for execution.']
    }
    Tempfile.create(['reviewed-datadog-manifest', '.json']) do |file|
      file.write(JSON.generate(manifest))
      file.flush
      yield file.path
    end
  end

  def command(env, *argv)
    Open3.capture3(env, 'ruby', File.join(ROOT, 'bin', 'rules-ctl'), *argv)
  end
end
