# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class ManifestBundleExecutionCliTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  DEFINITION = File.join(ROOT, 'examples', 'prometheus-stack', 'reviewed-checkout.rb')

  def test_confirmed_file_apply_requires_a_journal_directory_before_mutation
    Dir.mktmpdir do |dir|
      manifest_path = generate_manifest(dir)
      managed_dir = File.join(dir, 'managed')

      _stdout, stderr, status = command(
        'apply',
        '--provider=prometheus_stack',
        '--confirm',
        "--output-dir=#{managed_dir}",
        "--manifest=#{manifest_path}"
      )

      refute status.success?
      assert_includes stderr, 'live file-backed apply requires --journal-dir'
      refute File.exist?(File.join(managed_dir, 'checkout-api', 'prometheus_stack', 'manifest.json'))
    end
  end

  def test_confirmed_file_apply_outputs_result_and_durable_journal_reference
    Dir.mktmpdir do |dir|
      manifest_path = generate_manifest(dir)
      managed_dir = File.join(dir, 'managed')
      journal_dir = File.join(dir, 'journals')

      stdout, stderr, status = command(
        'apply',
        '--provider=prometheus_stack',
        '--confirm',
        "--output-dir=#{managed_dir}",
        "--journal-dir=#{journal_dir}",
        "--manifest=#{manifest_path}"
      )

      assert status.success?, stderr
      payload = JSON.parse(stdout).fetch(0)
      assert_equal 'succeeded', payload.dig('execution', 'result', 'status')
      assert_equal 'ProviderStateResult', payload.dig('execution', 'result', 'kind')
      assert_equal 'succeeded', payload.dig('execution', 'result', 'verification', 'status')
      assert_equal 4,
                   payload.dig('execution', 'result', 'verification', 'summary', 'succeeded_resources')
      journal_path = payload.dig('execution', 'operation_journal', 'path')
      assert journal_path.start_with?(journal_dir)
      assert File.exist?(journal_path)
      assert_equal 'succeeded', JSON.parse(File.read(journal_path)).fetch('status')
      status_stdout, status_stderr, journal_status = command('journal', 'status', journal_path)
      assert journal_status.success?, status_stderr
      journal_payload = JSON.parse(status_stdout)
      assert_equal 'succeeded', journal_payload.fetch('status')
      assert_equal 4, journal_payload.dig('summary', 'verification_succeeded_entries')
    end
  end

  def test_partial_file_apply_outputs_failure_result_and_exits_nonzero
    Dir.mktmpdir do |dir|
      manifest_path = generate_manifest(dir)
      managed_dir = File.join(dir, 'managed')
      journal_dir = File.join(dir, 'journals')
      generated_path = File.join(managed_dir, 'checkout-api', 'prometheus_stack', 'generated')
      FileUtils.mkdir_p(File.dirname(generated_path))
      File.write(generated_path, 'blocks generated directory creation')

      stdout, _stderr, status = command(
        'apply',
        '--provider=prometheus_stack',
        '--confirm',
        "--output-dir=#{managed_dir}",
        "--journal-dir=#{journal_dir}",
        "--manifest=#{manifest_path}"
      )

      refute status.success?
      payload = JSON.parse(stdout).fetch(0)
      assert_equal 'partial', payload.dig('execution', 'result', 'status')
      assert_equal %w[succeeded failed skipped skipped],
                   payload.dig('execution', 'result', 'operation_results').map { |result| result.fetch('status') }
      assert_includes payload.dig('execution', 'result', 'findings').map { |finding| finding.fetch('code') },
                      'partial_failure'
      assert_equal 'failed', payload.dig('execution', 'result', 'verification', 'status')
      assert_includes payload.dig('execution', 'result', 'findings').map { |finding| finding.fetch('code') },
                      'post_apply_verification_failed'
    end
  end

  def test_confirmed_file_prune_requires_a_journal_directory
    Dir.mktmpdir do |dir|
      manifest_path = generate_manifest(dir)

      _stdout, stderr, status = command(
        'prune',
        '--provider=prometheus_stack',
        '--confirm',
        "--output-dir=#{File.join(dir, 'managed')}",
        "--manifest=#{manifest_path}"
      )

      refute status.success?
      assert_includes stderr, 'live file-backed prune requires --journal-dir'
    end
  end

  private

  def generate_manifest(dir)
    generated_dir = File.join(dir, 'generated')
    stdout, stderr, status = command(
      'generate',
      '--provider=prometheus_stack',
      "--output-dir=#{generated_dir}",
      DEFINITION
    )
    assert status.success?, stderr.empty? ? stdout : stderr
    File.join(generated_dir, 'checkout-api', 'prometheus_stack', 'manifest.json')
  end

  def command(*argv)
    Open3.capture3('ruby', File.join(ROOT, 'bin', 'rules-ctl'), *argv)
  end
end
