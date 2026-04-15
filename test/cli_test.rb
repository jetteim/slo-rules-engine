# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'open3'
require 'tempfile'
require 'tmpdir'

class CLITest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def test_generate_fails_when_provider_binding_is_missing
    Tempfile.create(['missing-binding', '.rb']) do |file|
      file.write(<<~RUBY)
        require_relative '#{ROOT}/lib/sre'

        SRE.define do
          service 'catalog-api'
          owner 'catalog-platform'

          sli do
            uid 'http-requests'
            title 'HTTP requests'

            metric 'http_requests_total' do
              data_source 'otel'
              type 'counter'
            end

            instance do
              uid 'public-api'

              slo do
                uid 'successful-requests'
                objective 0.99
                success_selector status: 'success'
              end
            end
          end
        end
      RUBY
      file.flush

      stdout, _stderr, status = Open3.capture3('ruby', "#{ROOT}/bin/rules-ctl", 'generate', '--provider=datadog', file.path)
      payload = JSON.parse(stdout)

      refute status.success?
      assert_equal false, payload.fetch('valid')
      assert payload.fetch('errors').any? { |error| error.fetch('message').include?('missing datadog query binding') }
    end
  end

  def test_generate_writes_manifest_to_output_dir
    Dir.mktmpdir do |dir|
      stdout, _stderr, status = Open3.capture3(
        'ruby',
        "#{ROOT}/bin/rules-ctl",
        'generate',
        '--provider=datadog',
        "--output-dir=#{dir}",
        "#{ROOT}/examples/services/checkout.rb"
      )

      assert status.success?, stdout

      manifest_path = File.join(dir, 'checkout-api', 'datadog', 'manifest.json')
      assert File.exist?(manifest_path), "expected #{manifest_path} to exist"

      payload = JSON.parse(File.read(manifest_path))
      assert_equal 'checkout-api', payload.fetch('service')
      assert_equal 'datadog', payload.fetch('provider')
    end
  end

  def test_candidates_outputs_review_with_findings
    Tempfile.create(['signals', '.json']) do |file|
      file.write(JSON.generate([
        { kind: 'latency', metric: 'http_duration_seconds', user_visible: true },
        { kind: 'saturation', metric: 'heap_used', user_visible: false }
      ]))
      file.flush

      stdout, _stderr, status = Open3.capture3('ruby', "#{ROOT}/bin/rules-ctl", 'candidates', file.path)
      payload = JSON.parse(stdout)

      assert status.success?, stdout
      assert_equal 1, payload.fetch('candidates').length
      assert_equal ['non_user_visible'], payload.fetch('findings').map { |finding| finding.fetch('code') }
    end
  end

  def test_draft_definition_outputs_loadable_dsl_from_telemetry
    Tempfile.create(['signals', '.json']) do |signals_file|
      signals_file.write(JSON.generate([
        {
          kind: 'latency',
          metric: 'http.server.request.duration',
          user_visible: true,
          objective: 0.95,
          observations_per_second: 25,
          failed_observations_to_alert: 120
        },
        { kind: 'saturation', metric: 'runtime.heap.used', user_visible: false }
      ]))
      signals_file.flush

      stdout, stderr, status = Open3.capture3(
        'ruby',
        "#{ROOT}/bin/rules-ctl",
        'draft-definition',
        '--service=checkout-api',
        '--owner=payments-platform',
        signals_file.path
      )

      assert status.success?, stderr
      assert_includes stdout, "SRE.define"
      assert_includes stdout, "uid 'request-latency'"
      assert_includes stdout, 'measurement_details do'
      assert_includes stdout, 'miss_policy do'
      assert_includes stdout, "observability_handoff 'bind provider queries', 'generate decision dashboard'"
      refute_includes stdout, "uid 'resource-saturation'"

      Tempfile.create(['draft-definition', '.rb']) do |draft_file|
        draft_file.write(stdout)
        draft_file.flush

        validate_stdout, _validate_stderr, validate_status = Open3.capture3(
          'ruby',
          "#{ROOT}/bin/rules-ctl",
          'validate',
          draft_file.path
        )

        assert validate_status.success?, validate_stdout
        assert_equal true, JSON.parse(validate_stdout).fetch(0).fetch('valid')
      end
    end
  end

  def test_reality_check_reports_missing_telemetry
    Tempfile.create(['signals', '.json']) do |file|
      file.write(JSON.generate([{ metric: 'other.metric' }]))
      file.flush

      stdout, _stderr, status = Open3.capture3(
        'ruby',
        "#{ROOT}/bin/rules-ctl",
        'reality-check',
        '--provider=datadog',
        "--telemetry=#{file.path}",
        "#{ROOT}/examples/services/checkout.rb"
      )
      payload = JSON.parse(stdout)

      refute status.success?
      assert_equal false, payload.fetch('valid')
      assert_equal 'missing_provider_metric', payload.fetch('findings').fetch(0).fetch('code')
    end
  end

  def test_migration_report_exits_nonzero_for_findings
    Tempfile.create(['legacy-sld', '.rb']) do |file|
      file.write("datadog_trace_slo\n")
      file.flush

      stdout, _stderr, status = Open3.capture3('ruby', "#{ROOT}/bin/rules-ctl", 'migration-report', file.path)
      payload = JSON.parse(stdout)

      refute status.success?
      assert_equal false, payload.fetch('valid')
      assert_equal 'provider_specific_dsl', payload.fetch('findings').fetch(0).fetch('code')
    end
  end

  def test_model_report_command_outputs_json
    stdout, stderr, status = Open3.capture3('ruby', "#{ROOT}/bin/rules-ctl", 'model-report', "#{ROOT}/examples/services/checkout.rb")

    assert status.success?, stderr
    payload = JSON.parse(stdout)
    assert_equal 1, payload.fetch('service_count')
    assert_equal 1, payload.fetch('slo_count')
    assert_includes payload.fetch('observability_handoff_requests'), 'bind provider queries'
  end
end
