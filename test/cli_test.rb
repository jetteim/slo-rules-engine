# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'open3'
require 'tempfile'
require 'tmpdir'

class CLITest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def test_providers_list_includes_automation_metadata
    stdout, _stderr, status = Open3.capture3('ruby', "#{ROOT}/bin/rules-ctl", 'providers', 'list')

    assert status.success?, stdout
    providers = JSON.parse(stdout).to_h { |provider| [provider.fetch('key'), provider] }
    assert_equal 'live_api', providers.fetch('datadog').fetch('automation_mode')
    assert_includes providers.fetch('datadog').fetch('state_actions'), 'apply'
    assert_equal 'manifest_bundle', providers.fetch('prometheus_stack').fetch('automation_mode')
    assert_equal 'external_generator', providers.fetch('sloth').fetch('automation_mode')
  end

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

  def test_apply_datadog_dry_run_outputs_api_plan
    stdout, stderr, status = Open3.capture3(
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'apply',
      '--provider=datadog',
      '--dry-run',
      "#{ROOT}/examples/services/checkout.rb"
    )

    assert status.success?, stderr
    payload = JSON.parse(stdout).fetch(0)
    assert_equal 'datadog', payload.fetch('provider')
    assert_equal 'dry_run', payload.fetch('mode')
    assert_equal ['datadog.slo', 'datadog.monitor', 'datadog.monitor', 'datadog.dashboard'],
                 payload.fetch('operations').map { |operation| operation.fetch('target') }
  end

  def test_apply_datadog_confirm_requires_credentials
    stdout, stderr, status = Open3.capture3(
      { 'DD_API_KEY' => nil, 'DD_APP_KEY' => nil },
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'apply',
      '--provider=datadog',
      '--confirm',
      "#{ROOT}/examples/services/checkout.rb"
    )

    refute status.success?, stderr
    payload = JSON.parse(stdout)
    assert_equal false, payload.fetch('valid')
    assert_equal 'datadog', payload.fetch('provider')
    assert_equal 'missing_credentials', payload.fetch('error').fetch('code')
  end

  def test_apply_manifest_bundle_dry_run_outputs_plan_without_writing_file
    Dir.mktmpdir do |dir|
      stdout, stderr, status = Open3.capture3(
        'ruby',
        "#{ROOT}/bin/rules-ctl",
        'apply',
        '--provider=prometheus_stack',
        '--dry-run',
        "--output-dir=#{dir}",
        "#{ROOT}/examples/services/checkout.rb"
      )

      assert status.success?, stderr
      payload = JSON.parse(stdout).fetch(0)
      operation = payload.fetch('operations').fetch(0)
      manifest_path = File.join(dir, 'checkout-api', 'prometheus_stack', 'manifest.json')
      assert_equal 'prometheus_stack', payload.fetch('provider')
      assert_equal 'dry_run', payload.fetch('mode')
      assert_equal 'write', operation.fetch('action')
      assert_equal manifest_path, operation.fetch('payload').fetch('path')
      refute File.exist?(manifest_path), "expected dry-run not to write #{manifest_path}"
    end
  end

  def test_apply_manifest_bundle_confirm_writes_manifest_file
    Dir.mktmpdir do |dir|
      stdout, stderr, status = Open3.capture3(
        'ruby',
        "#{ROOT}/bin/rules-ctl",
        'apply',
        '--provider=sloth',
        '--confirm',
        "--output-dir=#{dir}",
        "#{ROOT}/examples/services/checkout.rb"
      )

      assert status.success?, stderr
      payload = JSON.parse(stdout).fetch(0)
      manifest_path = File.join(dir, 'checkout-api', 'sloth', 'manifest.json')
      assert_equal 'sloth', payload.fetch('provider')
      assert_equal 'live', payload.fetch('mode')
      assert File.exist?(manifest_path), "expected #{manifest_path} to exist"
      manifest = JSON.parse(File.read(manifest_path))
      assert_equal 'checkout-api', manifest.fetch('service')
      assert_equal 'sloth', manifest.fetch('provider')
    end
  end

  def test_apply_datadog_dry_run_accepts_reviewed_manifest_input
    generate_stdout, generate_stderr, generate_status = Open3.capture3(
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'generate',
      '--provider=datadog',
      "#{ROOT}/examples/services/checkout.rb"
    )
    assert generate_status.success?, generate_stderr
    manifest = JSON.parse(generate_stdout).fetch(0)

    Tempfile.create(['datadog-manifest', '.json']) do |file|
      file.write(JSON.generate(manifest))
      file.flush

      stdout, stderr, status = Open3.capture3(
        'ruby',
        "#{ROOT}/bin/rules-ctl",
        'apply',
        '--provider=datadog',
        '--dry-run',
        "--manifest=#{file.path}"
      )

      assert status.success?, stderr
      payload = JSON.parse(stdout).fetch(0)
      assert_equal 'datadog', payload.fetch('provider')
      assert_equal ['datadog.slo', 'datadog.monitor', 'datadog.monitor', 'datadog.dashboard'],
                   payload.fetch('operations').map { |operation| operation.fetch('target') }
    end
  end

  def test_apply_manifest_bundle_confirm_accepts_reviewed_manifest_input
    generate_stdout, generate_stderr, generate_status = Open3.capture3(
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'generate',
      '--provider=sloth',
      "#{ROOT}/examples/services/checkout.rb"
    )
    assert generate_status.success?, generate_stderr
    manifest = JSON.parse(generate_stdout).fetch(0)

    Tempfile.create(['sloth-manifest', '.json']) do |file|
      file.write(JSON.generate(manifest))
      file.flush

      Dir.mktmpdir do |dir|
        stdout, stderr, status = Open3.capture3(
          'ruby',
          "#{ROOT}/bin/rules-ctl",
          'apply',
          '--provider=sloth',
          '--confirm',
          "--output-dir=#{dir}",
          "--manifest=#{file.path}"
        )

        assert status.success?, stderr
        payload = JSON.parse(stdout).fetch(0)
        assert_equal 'sloth', payload.fetch('provider')
        manifest_path = File.join(dir, 'checkout-api', 'sloth', 'manifest.json')
        assert File.exist?(manifest_path), "expected #{manifest_path} to exist"
      end
    end
  end

  def test_lookup_telemetry_datadog_requires_credentials
    stdout, stderr, status = Open3.capture3(
      { 'DD_API_KEY' => nil, 'DD_APP_KEY' => nil },
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'lookup-telemetry',
      '--provider=datadog',
      '--metric=http.server.request.duration',
      '--kind=latency'
    )

    refute status.success?, stderr
    payload = JSON.parse(stdout)
    assert_equal false, payload.fetch('valid')
    assert_equal 'datadog', payload.fetch('provider')
    assert_equal 'missing_credentials', payload.fetch('error').fetch('code')
  end

  def test_lookup_telemetry_requires_metric
    _stdout, stderr, status = Open3.capture3(
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'lookup-telemetry',
      '--provider=prometheus_stack'
    )

    refute status.success?
    assert_includes stderr, 'missing --metric'
  end

  def test_discover_telemetry_datadog_requires_credentials
    stdout, stderr, status = Open3.capture3(
      { 'DD_API_KEY' => nil, 'DD_APP_KEY' => nil },
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'discover-telemetry',
      '--provider=datadog',
      '--service=checkout-api'
    )

    refute status.success?, stderr
    payload = JSON.parse(stdout)
    assert_equal false, payload.fetch('valid')
    assert_equal 'datadog', payload.fetch('provider')
    assert_equal 'missing_credentials', payload.fetch('error').fetch('code')
  end

  def test_discover_telemetry_requires_scope
    _stdout, stderr, status = Open3.capture3(
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'discover-telemetry',
      '--provider=prometheus_stack'
    )

    refute status.success?
    assert_includes stderr, 'missing discovery scope'
  end

  def test_discover_telemetry_rejects_datadog_host_plus_service_scope
    _stdout, stderr, status = Open3.capture3(
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'discover-telemetry',
      '--provider=datadog',
      '--service=checkout-api',
      '--host=checkout-host'
    )

    refute status.success?
    assert_includes stderr, 'datadog discovery cannot combine --host with --service or --selector'
  end

  def test_discover_telemetry_rejects_host_for_prometheus_provider
    _stdout, stderr, status = Open3.capture3(
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'discover-telemetry',
      '--provider=prometheus_stack',
      '--host=checkout-host'
    )

    refute status.success?
    assert_includes stderr, '--host is only supported for datadog discovery'
  end

  def test_candidates_accept_lookup_result_envelope
    Tempfile.create(['lookup-signals', '.json']) do |file|
      file.write(JSON.generate(
        provider: 'datadog',
        signals: [
          { kind: 'latency', metric: 'http.server.request.duration', user_visible: true, source: 'datadog' },
          { kind: 'saturation', metric: 'runtime.heap.used', user_visible: false, source: 'datadog' }
        ],
        findings: []
      ))
      file.flush

      stdout, _stderr, status = Open3.capture3('ruby', "#{ROOT}/bin/rules-ctl", 'candidates', file.path)
      payload = JSON.parse(stdout)

      assert status.success?, stdout
      assert_equal 1, payload.fetch('candidates').length
      assert_equal 'request-latency', payload.fetch('candidates').fetch(0).fetch('sli_uid')
      assert_equal ['non_user_visible'], payload.fetch('findings').map { |finding| finding.fetch('code') }
    end
  end

  def test_draft_definition_accepts_lookup_result_envelope
    Tempfile.create(['lookup-signals', '.json']) do |file|
      file.write(JSON.generate(
        provider: 'datadog',
        signals: [
          {
            kind: 'latency',
            metric: 'http.server.request.duration',
            user_visible: true,
            source: 'datadog',
            observations_per_second: 25,
            failed_observations_to_alert: 120
          },
          { kind: 'saturation', metric: 'runtime.heap.used', user_visible: false, source: 'datadog' }
        ],
        findings: []
      ))
      file.flush

      stdout, stderr, status = Open3.capture3(
        'ruby',
        "#{ROOT}/bin/rules-ctl",
        'draft-definition',
        '--service=checkout-api',
        '--owner=payments-platform',
        file.path
      )

      assert status.success?, stderr
      assert_includes stdout, "metric 'http.server.request.duration'"
      refute_includes stdout, "metric 'runtime.heap.used'"
    end
  end

  def test_generate_outputs_sloth_provider_manifest
    stdout, stderr, status = Open3.capture3(
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'generate',
      '--provider=sloth',
      "#{ROOT}/examples/services/checkout.rb"
    )

    assert status.success?, stderr
    payload = JSON.parse(stdout).fetch(0)
    spec = payload.fetch('artifacts').fetch('sloth_specs').fetch(0)
    assert_equal 'sloth', payload.fetch('provider')
    assert_equal 'prometheus/v1', spec.fetch('version')
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

  def test_reality_check_reads_lookup_result_findings
    Tempfile.create(['lookup-result', '.json']) do |file|
      file.write(JSON.generate(
        provider: 'datadog',
        signals: [{ metric: 'http.server.request.duration' }],
        findings: [
          {
            code: 'missing_backend_series',
            provider: 'datadog',
            metric: 'http.server.request.duration',
            message: 'no series'
          }
        ]
      ))
      file.flush

      stdout, _stderr, status = Open3.capture3(
        'ruby',
        "#{ROOT}/bin/rules-ctl",
        'reality-check',
        '--provider=datadog',
        "--lookup-result=#{file.path}",
        "#{ROOT}/examples/services/checkout.rb"
      )
      payload = JSON.parse(stdout)

      refute status.success?
      assert_equal 'missing_backend_series', payload.fetch('findings').fetch(0).fetch('code')
    end
  end

  def test_reality_check_online_requires_explicit_lookup_flags
    stdout, _stderr, status = Open3.capture3(
      { 'DD_API_KEY' => nil, 'DD_APP_KEY' => nil },
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'reality-check',
      '--provider=datadog',
      '--online',
      "#{ROOT}/examples/services/checkout.rb"
    )
    payload = JSON.parse(stdout)

    refute status.success?
    assert_equal 'missing_credentials', payload.fetch('error').fetch('code')
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
