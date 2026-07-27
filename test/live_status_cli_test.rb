# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require_relative 'support/cli_helpers'
require_relative 'support/release_bundle_fixtures'

class LiveStatusCliTest < Minitest::Test
  include CliHelpers
  include ReleaseBundleFixtures

  REVIEWED_AT = '2026-07-27T12:00:00Z'

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
      assert requests.all? { |request| request.start_with?('status.example.test /api/v1/query?') }
    end
  end

  def test_status_aggregates_a_release_bundle_and_makes_unsupported_targets_explicit
    Dir.mktmpdir do |dir|
      fixture = write_release_bundle_fixture(
        dir,
        providers: %w[prometheus_stack sloth]
      )
      bundle = SloRulesEngine::ReleaseBundle::Builder.new.build(
        fixture.fetch(:artifact_index),
        reviewer: 'team/payments-sre',
        reviewed_at: REVIEWED_AT
      )
      bundle_path = File.join(dir, 'release-bundle.json')
      output_path = File.join(dir, 'live-status.json')
      request_log_path = File.join(dir, 'requests.log')
      File.write(bundle_path, JSON.pretty_generate(bundle))
      fake_http = File.join(dir, 'fake_prometheus_status_http.rb')
      FileUtils.cp(File.expand_path('support/fake_prometheus_status_http.rb', __dir__), fake_http)

      stdout, stderr, status = rules_ctl(
        'status',
        "--bundle=#{bundle_path}",
        '--target-base-url=checkout-api/prometheus_stack=http://bundle-prometheus.example.test',
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
      assert_equal 'slo-rules-engine/live-slo-status-aggregate/v1', payload.fetch('schema_version')
      assert_equal 'release_bundle', payload.fetch('scope')
      assert_equal 1, payload.fetch('summary').fetch('reported_targets')
      assert_equal 1, payload.fetch('summary').fetch('unsupported_targets')
      assert_equal false, payload.fetch('summary').fetch('coverage_complete')
      assert_equal %w[reported unsupported], payload.fetch('targets').map { |target| target.fetch('outcome') }
      refute_includes stdout, 'bundle-prometheus.example.test'
      requests = File.readlines(request_log_path, chomp: true)
      assert_equal 8, requests.length
      assert requests.all? { |request| request.start_with?('bundle-prometheus.example.test ') }
    end
  end

  def test_status_portfolio_preserves_one_failed_target_as_unverifiable
    Dir.mktmpdir do |dir|
      portfolio_path = write_live_status_portfolio(dir)
      output_path = File.join(dir, 'portfolio-status.json')
      request_log_path = File.join(dir, 'requests.log')
      fake_http = File.join(dir, 'fake_prometheus_status_http.rb')
      FileUtils.cp(File.expand_path('support/fake_prometheus_status_http.rb', __dir__), fake_http)

      stdout, stderr, status = rules_ctl(
        'status',
        "--portfolio=#{portfolio_path}",
        '--target-base-url=checkout-api/prometheus_stack=http://checkout-prometheus.example.test',
        '--target-base-url=search-api/prometheus_stack=http://search-prometheus.example.test',
        "--output=#{output_path}",
        env: {
          'RUBYOPT' => "-r#{fake_http}",
          'PROMETHEUS_REQUEST_LOG' => request_log_path,
          'PROMETHEUS_FAIL_HOST' => 'search-prometheus.example.test'
        }
      )

      assert status.success?, stderr
      assert_empty stderr
      payload = JSON.parse(stdout)
      assert_equal 2, payload.fetch('summary').fetch('reported_targets')
      assert_equal 1, payload.fetch('summary').fetch('healthy')
      assert_equal 1, payload.fetch('summary').fetch('unverifiable')
      assert_equal true, payload.fetch('summary').fetch('coverage_complete')
      assert_equal false, payload.fetch('summary').fetch('evidence_complete')
      failed = payload.fetch('targets').find { |target| target.fetch('uid') == 'search-api/prometheus_stack' }
      assert_equal 'unverifiable', failed.fetch('report').fetch('statuses').fetch(0).fetch('state')
      refute_includes stdout, 'private backend failure'
      refute_includes stdout, 'checkout-prometheus.example.test'
      refute_includes stdout, 'search-prometheus.example.test'
      assert_equal 16, File.readlines(request_log_path).length
    end
  end

  def test_status_rejects_a_stale_bundle_before_backend_access
    Dir.mktmpdir do |dir|
      fixture = write_release_bundle_fixture(dir)
      bundle = SloRulesEngine::ReleaseBundle::Builder.new.build(
        fixture.fetch(:artifact_index),
        reviewer: 'team/payments-sre',
        reviewed_at: REVIEWED_AT
      )
      bundle_path = File.join(dir, 'release-bundle.json')
      request_log_path = File.join(dir, 'requests.log')
      File.write(bundle_path, JSON.pretty_generate(bundle))
      File.write(fixture.fetch(:manifest), "{}\n")
      fake_http = File.join(dir, 'fake_prometheus_status_http.rb')
      FileUtils.cp(File.expand_path('support/fake_prometheus_status_http.rb', __dir__), fake_http)

      stdout, _stderr, status = rules_ctl(
        'status',
        "--bundle=#{bundle_path}",
        '--target-base-url=checkout-api/prometheus_stack=http://bundle-prometheus.example.test',
        env: {
          'RUBYOPT' => "-r#{fake_http}",
          'PROMETHEUS_REQUEST_LOG' => request_log_path
        }
      )

      refute status.success?
      payload = JSON.parse(stdout)
      assert_equal 'stale_live_status_bundle', payload.fetch('error').fetch('code')
      refute File.exist?(request_log_path)
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

  private

  def write_live_status_portfolio(dir)
    manifests = %w[checkout-api search-api].map do |service|
      manifest = replace_live_status_service(
        JSON.parse(JSON.generate(reviewed_provider_manifest('prometheus_stack'))),
        service
      )
      path = File.join(dir, "#{service}.manifest.json")
      File.write(path, JSON.pretty_generate(manifest))
      [service, File.basename(path)]
    end
    path = File.join(dir, 'portfolio.json')
    File.write(
      path,
      JSON.pretty_generate(
        schema_version: 'slo-rules-engine/live-status-portfolio/v1',
        kind: 'LiveStatusPortfolio',
        targets: manifests.map do |service, manifest|
          {
            uid: "#{service}/prometheus_stack",
            manifest: manifest
          }
        end
      )
    )
    path
  end

  def replace_live_status_service(value, service)
    case value
    when Hash
      value.transform_values { |entry| replace_live_status_service(entry, service) }
    when Array
      value.map { |entry| replace_live_status_service(entry, service) }
    when String
      value
        .gsub('checkout-api', service)
        .gsub('checkout_api', service.tr('-', '_'))
        .gsub('checkout-prod', "#{service}-prod")
    else
      value
    end
  end
end
