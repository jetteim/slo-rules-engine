# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require_relative 'support/cli_helpers'

class LiveStatusCliTest < Minitest::Test
  include CliHelpers

  def test_status_reads_one_reviewed_manifest_and_writes_the_stdout_report
    Dir.mktmpdir do |dir|
      manifest_path = File.join(dir, 'manifest.json')
      output_path = File.join(dir, 'status.json')
      request_log_path = File.join(dir, 'requests.log')
      File.write(manifest_path, JSON.pretty_generate(reviewed_manifest('prometheus_stack')))
      fake_http = File.join(dir, 'fake_prometheus_status_http.rb')
      FileUtils.cp(File.expand_path('support/fake_prometheus_status_http.rb', __dir__), fake_http)

      stdout, stderr, status = rules_ctl(
        'status',
        '--provider=prometheus_stack',
        "--manifest=#{manifest_path}",
        '--base-url=http://status.example.test',
        '--max-age-seconds=300',
        "--output=#{output_path}",
        env: {
          'RUBYOPT' => "-r#{fake_http}",
          'PROMETHEUS_REQUEST_LOG' => request_log_path
        }
      )

      assert status.success?, stderr
      assert_empty stderr
      payload = JSON.parse(stdout)
      assert_equal payload, JSON.parse(File.read(output_path))
      assert_equal 'slo-rules-engine/live-slo-status/v1', payload.fetch('schema_version')
      assert_equal 'LiveSLOStatusReport', payload.fetch('kind')
      assert_equal 'healthy', payload.fetch('statuses').fetch(0).fetch('state')
      requests = File.readlines(request_log_path, chomp: true)
      assert_equal 8, requests.length
      assert requests.all? { |request| request.start_with?('/api/v1/query?') }
    end
  end

  def test_status_rejects_unreviewed_manifest_before_backend_access
    with_temp_json('unreviewed-manifest', generate_manifest('prometheus_stack')) do |manifest_file|
      stdout, _stderr, status = rules_ctl(
        'status',
        '--provider=prometheus_stack',
        "--manifest=#{manifest_file.path}",
        '--base-url=http://127.0.0.1:1'
      )

      refute status.success?
      payload = JSON.parse(stdout)
      assert_equal 'missing_review_evidence', payload.fetch('error').fetch('code')
      assert_equal 'prometheus_stack', payload.fetch('provider')
    end
  end

  def test_status_explicitly_defers_datadog_live_read
    with_temp_json('datadog-manifest', reviewed_manifest('datadog')) do |manifest_file|
      stdout, _stderr, status = rules_ctl(
        'status',
        '--provider=datadog',
        "--manifest=#{manifest_file.path}"
      )

      refute status.success?
      payload = JSON.parse(stdout)
      assert_equal 'unsupported_live_status_provider', payload.fetch('error').fetch('code')
      assert_includes payload.fetch('error').fetch('message'), 'prometheus_stack'
    end
  end
end
