# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'open3'
require 'fileutils'
require 'tempfile'
require 'tmpdir'
require 'yaml'

class CLITest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def with_review_provenance(manifest)
    manifest.merge(
      'review_provenance' => {
        'label' => 'checkout-prod',
        'provider' => 'datadog',
        'accepted_candidate_uids' => ['request-latency'],
        'notes' => ['Latency accepted.']
      }
    )
  end

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

  def test_generate_output_dir_writes_manifest_review_report
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
      report_path = File.join(dir, 'manifest-review', 'datadog.json')
      assert File.exist?(report_path), "expected #{report_path} to exist"

      report = JSON.parse(File.read(report_path))
      assert_equal false, report.fetch('valid')
      assert_equal report_path, report.fetch('report').fetch('path')
      assert_equal 1, report.fetch('summary').fetch('missing_provenance_manifests')
      assert_equal 'missing_review_provenance', report.fetch('manifests').fetch(0).fetch('findings').fetch(0).fetch('code')
    end
  end

  def test_manifest_review_reports_generated_manifest_provenance_gaps
    stdout, _stderr, status = Open3.capture3(
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'manifest-review',
      '--provider=datadog',
      "#{ROOT}/examples/services/checkout.rb"
    )

    payload = JSON.parse(stdout)
    refute status.success?
    assert_equal false, payload.fetch('valid')
    assert_equal 1, payload.fetch('summary').fetch('missing_provenance_manifests')
    assert_equal 'missing_provenance', payload.fetch('manifests').fetch(0).fetch('status')
    assert_equal 'missing_review_provenance', payload.fetch('manifests').fetch(0).fetch('findings').fetch(0).fetch('code')
  end

  def test_manifest_review_accepts_reviewed_manifest_input
    generate_stdout, generate_stderr, generate_status = Open3.capture3(
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'generate',
      '--provider=datadog',
      "#{ROOT}/examples/services/checkout.rb"
    )
    assert generate_status.success?, generate_stderr
    manifest = with_review_provenance(JSON.parse(generate_stdout).fetch(0))

    Tempfile.create(['reviewed-manifest', '.json']) do |file|
      file.write(JSON.pretty_generate(manifest))
      file.flush

      stdout, stderr, status = Open3.capture3(
        'ruby',
        "#{ROOT}/bin/rules-ctl",
        'manifest-review',
        '--provider=datadog',
        "--manifest=#{file.path}"
      )

      assert status.success?, stderr
      payload = JSON.parse(stdout)
      assert_equal true, payload.fetch('valid')
      assert_equal 1, payload.fetch('summary').fetch('reviewed_manifests')
      assert_equal 1, payload.fetch('summary').fetch('accepted_candidate_total')
      assert_equal 'reviewed', payload.fetch('manifests').fetch(0).fetch('status')
    end
  end

  def test_manifest_review_links_findings_to_handoff_dir
    generate_stdout, generate_stderr, generate_status = Open3.capture3(
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'generate',
      '--provider=datadog',
      "#{ROOT}/examples/services/checkout.rb"
    )
    assert generate_status.success?, generate_stderr
    manifest = with_review_provenance(JSON.parse(generate_stdout).fetch(0))
    manifest.fetch('review_provenance')['accepted_candidate_uids'] = []

    Tempfile.create(['incomplete-reviewed-manifest', '.json']) do |manifest_file|
      manifest_file.write(JSON.pretty_generate(manifest))
      manifest_file.flush

      Dir.mktmpdir do |handoff_dir|
        handoff_path = File.join(handoff_dir, 'checkout-prod.handoff.json')
        File.write(handoff_path, JSON.pretty_generate('label' => 'checkout-prod'))

        stdout, _stderr, status = Open3.capture3(
          'ruby',
          "#{ROOT}/bin/rules-ctl",
          'manifest-review',
          '--provider=datadog',
          "--manifest=#{manifest_file.path}",
          "--handoff-dir=#{handoff_dir}"
        )

        payload = JSON.parse(stdout)
        refute status.success?
        manifest_report = payload.fetch('manifests').fetch(0)
        assert_equal handoff_path, manifest_report.fetch('handoff').fetch('path')
        assert_equal true, manifest_report.fetch('handoff').fetch('exists')
        assert_equal handoff_path, manifest_report.fetch('findings').fetch(0).fetch('handoff_file')
      end
    end
  end

  def test_manifest_review_writes_explicit_output_report
    generate_stdout, generate_stderr, generate_status = Open3.capture3(
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'generate',
      '--provider=datadog',
      "#{ROOT}/examples/services/checkout.rb"
    )
    assert generate_status.success?, generate_stderr
    manifest = with_review_provenance(JSON.parse(generate_stdout).fetch(0))

    Tempfile.create(['reviewed-manifest', '.json']) do |manifest_file|
      manifest_file.write(JSON.pretty_generate(manifest))
      manifest_file.flush

      Tempfile.create(['manifest-review-report', '.json']) do |report_file|
        stdout, stderr, status = Open3.capture3(
          'ruby',
          "#{ROOT}/bin/rules-ctl",
          'manifest-review',
          '--provider=datadog',
          "--manifest=#{manifest_file.path}",
          "--output=#{report_file.path}"
        )

        assert status.success?, stderr
        stdout_payload = JSON.parse(stdout)
        file_payload = JSON.parse(File.read(report_file.path))
        assert_equal true, file_payload.fetch('valid')
        assert_equal stdout_payload, file_payload
      end
    end
  end

  def test_manifest_review_output_includes_saved_report_path
    generate_stdout, generate_stderr, generate_status = Open3.capture3(
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'generate',
      '--provider=datadog',
      "#{ROOT}/examples/services/checkout.rb"
    )
    assert generate_status.success?, generate_stderr
    manifest = with_review_provenance(JSON.parse(generate_stdout).fetch(0))

    Tempfile.create(['reviewed-manifest', '.json']) do |manifest_file|
      manifest_file.write(JSON.pretty_generate(manifest))
      manifest_file.flush

      Tempfile.create(['manifest-review-report', '.json']) do |report_file|
        stdout, stderr, status = Open3.capture3(
          'ruby',
          "#{ROOT}/bin/rules-ctl",
          'manifest-review',
          '--provider=datadog',
          "--manifest=#{manifest_file.path}",
          "--output=#{report_file.path}"
        )

        assert status.success?, stderr
        payload = JSON.parse(stdout)
        assert_equal report_file.path, payload.fetch('report').fetch('path')
        assert_equal report_file.path, JSON.parse(File.read(report_file.path)).fetch('report').fetch('path')
      end
    end
  end

  def test_manifest_review_report_option_validates_saved_report_freshness
    generate_stdout, generate_stderr, generate_status = Open3.capture3(
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'generate',
      '--provider=datadog',
      "#{ROOT}/examples/services/checkout.rb"
    )
    assert generate_status.success?, generate_stderr
    manifest = with_review_provenance(JSON.parse(generate_stdout).fetch(0))

    Tempfile.create(['reviewed-manifest', '.json']) do |manifest_file|
      manifest_file.write(JSON.pretty_generate(manifest))
      manifest_file.flush

      Dir.mktmpdir do |handoff_dir|
        handoff_path = File.join(handoff_dir, 'checkout-prod.handoff.json')
        File.write(
          handoff_path,
          JSON.pretty_generate(
            label: 'checkout-prod',
            provider: 'datadog',
            review: {
              status: 'reviewed',
              accepted_candidate_uids: ['request-latency'],
              rejected_candidate_uids: [],
              notes: ['Latency accepted.']
            }
          )
        )

        report_file = File.join(handoff_dir, 'manifest-review.json')
        stdout, stderr, status = Open3.capture3(
          'ruby',
          "#{ROOT}/bin/rules-ctl",
          'manifest-review',
          '--provider=datadog',
          "--manifest=#{manifest_file.path}",
          "--handoff-dir=#{handoff_dir}",
          "--output=#{report_file}"
        )
        assert status.success?, stderr
        stale = JSON.parse(stdout)
        stale.fetch('freshness')['manifest_fingerprint'] = 'outdated'
        File.write(report_file, JSON.pretty_generate(stale))

        stdout, _stderr, status = Open3.capture3(
          'ruby',
          "#{ROOT}/bin/rules-ctl",
          'manifest-review',
          '--provider=datadog',
          "--manifest=#{manifest_file.path}",
          "--handoff-dir=#{handoff_dir}",
          "--report=#{report_file}"
        )

        payload = JSON.parse(stdout)
        refute status.success?
        assert_equal false, payload.fetch('saved_report').fetch('fresh')
        assert_equal 'stale_manifest_review_report', payload.fetch('saved_report').fetch('findings').fetch(0).fetch('code')
      end
    end
  end

  def test_manifest_review_report_option_flags_stale_handoff_freshness
    generate_stdout, generate_stderr, generate_status = Open3.capture3(
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'generate',
      '--provider=datadog',
      "#{ROOT}/examples/services/checkout.rb"
    )
    assert generate_status.success?, generate_stderr
    manifest = with_review_provenance(JSON.parse(generate_stdout).fetch(0))

    Tempfile.create(['reviewed-manifest', '.json']) do |manifest_file|
      manifest_file.write(JSON.pretty_generate(manifest))
      manifest_file.flush

      Dir.mktmpdir do |handoff_dir|
        handoff_path = File.join(handoff_dir, 'checkout-prod.handoff.json')
        handoff_packet = {
          label: 'checkout-prod',
          provider: 'datadog',
          review: {
            status: 'reviewed',
            accepted_candidate_uids: ['request-latency'],
            rejected_candidate_uids: [],
            notes: ['Latency accepted.']
          }
        }
        File.write(handoff_path, JSON.pretty_generate(handoff_packet))

        report_file = File.join(handoff_dir, 'manifest-review.json')
        _stdout, stderr, status = Open3.capture3(
          'ruby',
          "#{ROOT}/bin/rules-ctl",
          'manifest-review',
          '--provider=datadog',
          "--manifest=#{manifest_file.path}",
          "--handoff-dir=#{handoff_dir}",
          "--output=#{report_file}"
        )
        assert status.success?, stderr

        handoff_packet[:metadata] = { generated_by: 'reviewer-note' }
        File.write(handoff_path, JSON.pretty_generate(handoff_packet))

        stdout, _stderr, status = Open3.capture3(
          'ruby',
          "#{ROOT}/bin/rules-ctl",
          'manifest-review',
          '--provider=datadog',
          "--manifest=#{manifest_file.path}",
          "--handoff-dir=#{handoff_dir}",
          "--report=#{report_file}"
        )

        payload = JSON.parse(stdout)
        refute status.success?
        assert_equal true, payload.fetch('valid')
        assert_equal 'stale_handoff_review_report', payload.fetch('saved_report').fetch('findings').fetch(0).fetch('code')
      end
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
    assert_equal 4, payload.fetch('summary').fetch('total_operations')
    assert_equal 4, payload.fetch('summary').fetch('actionable_operations')
    assert_equal 0, payload.fetch('summary').fetch('destructive_operations')
    assert_equal ['datadog.slo', 'datadog.monitor', 'datadog.monitor', 'datadog.dashboard'],
                 payload.fetch('operations').map { |operation| operation.fetch('target') }
  end

  def test_apply_datadog_confirm_requires_credentials
    generate_stdout, generate_stderr, generate_status = Open3.capture3(
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'generate',
      '--provider=datadog',
      "#{ROOT}/examples/services/checkout.rb"
    )
    assert generate_status.success?, generate_stderr
    manifest = with_review_provenance(JSON.parse(generate_stdout).fetch(0))

    Tempfile.create(['datadog-live-manifest', '.json']) do |file|
      file.write(JSON.generate(manifest))
      file.flush

      stdout, stderr, status = Open3.capture3(
        { 'DD_API_KEY' => nil, 'DD_APP_KEY' => nil },
        'ruby',
        "#{ROOT}/bin/rules-ctl",
        'apply',
        '--provider=datadog',
        '--confirm',
        "--manifest=#{file.path}"
      )

      refute status.success?, stderr
      payload = JSON.parse(stdout)
      assert_equal false, payload.fetch('valid')
      assert_equal 'datadog', payload.fetch('provider')
      assert_equal 'missing_credentials', payload.fetch('error').fetch('code')
    end
  end

  def test_apply_confirm_with_handoff_dir_blocks_stale_review_evidence
    generate_stdout, generate_stderr, generate_status = Open3.capture3(
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'generate',
      '--provider=datadog',
      "#{ROOT}/examples/services/checkout.rb"
    )
    assert generate_status.success?, generate_stderr
    manifest = with_review_provenance(JSON.parse(generate_stdout).fetch(0))

    Tempfile.create(['datadog-stale-manifest', '.json']) do |file|
      file.write(JSON.generate(manifest))
      file.flush

      Dir.mktmpdir do |handoff_dir|
        File.write(
          File.join(handoff_dir, 'checkout-prod.handoff.json'),
          JSON.pretty_generate(
            label: 'checkout-prod',
            provider: 'datadog',
            review: {
              status: 'reviewed',
              accepted_candidate_uids: ['request-errors'],
              rejected_candidate_uids: ['request-latency'],
              notes: ['Errors accepted after review.']
            }
          )
        )

        stdout, stderr, status = Open3.capture3(
          { 'DD_API_KEY' => nil, 'DD_APP_KEY' => nil },
          'ruby',
          "#{ROOT}/bin/rules-ctl",
          'apply',
          '--provider=datadog',
          '--confirm',
          "--manifest=#{file.path}",
          "--handoff-dir=#{handoff_dir}"
        )

        refute status.success?, stderr
        payload = JSON.parse(stdout)
        assert_equal 'invalid_manifest_review', payload.fetch('error').fetch('code')
        assert_equal 1, payload.fetch('manifest_review').fetch('summary').fetch('stale_provenance_manifests')
        assert_equal 'stale_provenance', payload.fetch('manifest_review').fetch('manifests').fetch(0).fetch('status')
      end
    end
  end

  def test_apply_confirm_with_current_handoff_reaches_provider_path
    generate_stdout, generate_stderr, generate_status = Open3.capture3(
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'generate',
      '--provider=datadog',
      "#{ROOT}/examples/services/checkout.rb"
    )
    assert generate_status.success?, generate_stderr
    manifest = with_review_provenance(JSON.parse(generate_stdout).fetch(0))

    Tempfile.create(['datadog-current-manifest', '.json']) do |file|
      file.write(JSON.generate(manifest))
      file.flush

      Dir.mktmpdir do |handoff_dir|
        File.write(
          File.join(handoff_dir, 'checkout-prod.handoff.json'),
          JSON.pretty_generate(
            label: 'checkout-prod',
            provider: 'datadog',
            review: {
              status: 'reviewed',
              accepted_candidate_uids: ['request-latency'],
              rejected_candidate_uids: [],
              notes: ['Latency accepted.']
            }
          )
        )

        stdout, stderr, status = Open3.capture3(
          { 'DD_API_KEY' => nil, 'DD_APP_KEY' => nil },
          'ruby',
          "#{ROOT}/bin/rules-ctl",
          'apply',
          '--provider=datadog',
          '--confirm',
          "--manifest=#{file.path}",
          "--handoff-dir=#{handoff_dir}"
        )

        refute status.success?, stderr
        assert_equal 'missing_credentials', JSON.parse(stdout).fetch('error').fetch('code')
      end
    end
  end

  def test_apply_confirm_with_review_report_blocks_stale_saved_report
    current_manifest = with_review_provenance(
      JSON.parse(
        Open3.capture3(
          'ruby',
          "#{ROOT}/bin/rules-ctl",
          'generate',
          '--provider=datadog',
          "#{ROOT}/examples/services/checkout.rb"
        ).fetch(0)
      ).fetch(0)
    )
    old_manifest = Marshal.load(Marshal.dump(current_manifest))
    old_manifest.fetch('review_provenance')['accepted_candidate_uids'] = ['request-errors']

    Tempfile.create(['current-datadog-manifest', '.json']) do |manifest_file|
      manifest_file.write(JSON.generate(current_manifest))
      manifest_file.flush

      Tempfile.create(['old-datadog-manifest', '.json']) do |old_manifest_file|
        old_manifest_file.write(JSON.generate(old_manifest))
        old_manifest_file.flush

        Dir.mktmpdir do |handoff_dir|
          File.write(
            File.join(handoff_dir, 'checkout-prod.handoff.json'),
            JSON.pretty_generate(
              label: 'checkout-prod',
              provider: 'datadog',
              review: {
                status: 'reviewed',
                accepted_candidate_uids: ['request-latency'],
                rejected_candidate_uids: [],
                notes: ['Latency accepted.']
              }
            )
          )

          report_file = File.join(handoff_dir, 'old-manifest-review.json')
          _stdout, stderr, status = Open3.capture3(
            'ruby',
            "#{ROOT}/bin/rules-ctl",
            'manifest-review',
            '--provider=datadog',
            "--manifest=#{old_manifest_file.path}",
            "--output=#{report_file}"
          )
          assert status.success?, stderr

          stdout, _stderr, status = Open3.capture3(
            { 'DD_API_KEY' => nil, 'DD_APP_KEY' => nil },
            'ruby',
            "#{ROOT}/bin/rules-ctl",
            'apply',
            '--provider=datadog',
            '--confirm',
            "--manifest=#{manifest_file.path}",
            "--handoff-dir=#{handoff_dir}",
            "--review-report=#{report_file}"
          )

          payload = JSON.parse(stdout)
          refute status.success?
          assert_equal 'stale_manifest_review_report', payload.fetch('error').fetch('code')
          assert_equal false, payload.fetch('saved_report').fetch('fresh')
        end
      end
    end
  end

  def test_apply_confirm_requires_manifest_review_evidence
    generate_stdout, generate_stderr, generate_status = Open3.capture3(
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'generate',
      '--provider=datadog',
      "#{ROOT}/examples/services/checkout.rb"
    )
    assert generate_status.success?, generate_stderr
    manifest = JSON.parse(generate_stdout).fetch(0)

    Tempfile.create(['datadog-unreviewed-manifest', '.json']) do |file|
      file.write(JSON.generate(manifest))
      file.flush

      stdout, stderr, status = Open3.capture3(
        { 'DD_API_KEY' => nil, 'DD_APP_KEY' => nil },
        'ruby',
        "#{ROOT}/bin/rules-ctl",
        'apply',
        '--provider=datadog',
        '--confirm',
        "--manifest=#{file.path}"
      )

      refute status.success?, stderr
      payload = JSON.parse(stdout)
      assert_equal false, payload.fetch('valid')
      assert_equal 'missing_review_evidence', payload.fetch('error').fetch('code')
      assert payload.fetch('errors').any? { |error| error.fetch('path') == 'manifests[0].review_provenance' }
    end
  end

  def test_apply_confirm_requires_reviewed_manifest_input
    _stdout, stderr, status = Open3.capture3(
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'apply',
      '--provider=datadog',
      '--confirm',
      "#{ROOT}/examples/services/checkout.rb"
    )

    refute status.success?
    assert_includes stderr, 'live apply requires --manifest'
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
    generate_stdout, generate_stderr, generate_status = Open3.capture3(
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'generate',
      '--provider=sloth',
      "#{ROOT}/examples/services/checkout.rb"
    )
    assert generate_status.success?, generate_stderr
    manifest = with_review_provenance(JSON.parse(generate_stdout).fetch(0))

    Tempfile.create(['sloth-live-manifest', '.json']) do |file|
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
        manifest_path = File.join(dir, 'checkout-api', 'sloth', 'manifest.json')
        spec_path = File.join(dir, 'checkout-api', 'sloth', 'generated', 'sloth.yaml')
        assert_equal 'sloth', payload.fetch('provider')
        assert_equal 'live', payload.fetch('mode')
        assert_equal %w[write write handoff], payload.fetch('operations').map { |operation| operation.fetch('action') }
        assert File.exist?(manifest_path), "expected #{manifest_path} to exist"
        assert File.exist?(spec_path), "expected #{spec_path} to exist"
        manifest = JSON.parse(File.read(manifest_path))
        spec = YAML.safe_load(File.read(spec_path), permitted_classes: [], aliases: false)
        assert_equal 'checkout-api', manifest.fetch('service')
        assert_equal 'sloth', manifest.fetch('provider')
        assert_equal 'prometheus/v1', spec.fetch('version')
        assert_equal 'checkout-api', spec.fetch('service')
        assert_equal spec_path, payload.fetch('operations').fetch(2).fetch('payload').fetch('input_spec')
      end
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
    manifest = with_review_provenance(JSON.parse(generate_stdout).fetch(0))

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

  def test_apply_datadog_dry_run_rejects_invalid_reviewed_manifest_schema
    generate_stdout, generate_stderr, generate_status = Open3.capture3(
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'generate',
      '--provider=datadog',
      "#{ROOT}/examples/services/checkout.rb"
    )
    assert generate_status.success?, generate_stderr
    manifest = with_review_provenance(JSON.parse(generate_stdout).fetch(0))
    manifest.fetch('artifacts').fetch('slos').fetch(0).fetch('query').delete('success_selector')

    Tempfile.create(['datadog-invalid-manifest', '.json']) do |file|
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

      refute status.success?, stderr
      payload = JSON.parse(stdout)
      assert_equal false, payload.fetch('valid')
      assert_equal 'invalid_manifest_schema', payload.fetch('error').fetch('code')
      assert payload.fetch('errors').any? do |error|
        error.fetch('path') == 'artifacts.slos[0].query.success_selector'
      end
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
    manifest = with_review_provenance(JSON.parse(generate_stdout).fetch(0))

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

  def test_diff_manifest_bundle_accepts_reviewed_manifest_input
    generate_stdout, generate_stderr, generate_status = Open3.capture3(
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'generate',
      '--provider=sloth',
      "#{ROOT}/examples/services/checkout.rb"
    )
    assert generate_status.success?, generate_stderr
    manifest = JSON.parse(generate_stdout).fetch(0)

    Tempfile.create(['sloth-diff-manifest', '.json']) do |file|
      file.write(JSON.generate(manifest))
      file.flush

      Dir.mktmpdir do |dir|
        managed_path = File.join(dir, 'checkout-api', 'sloth', 'manifest.json')
        FileUtils.mkdir_p(File.dirname(managed_path))
        existing = Marshal.load(Marshal.dump(manifest))
        existing.fetch('artifacts').fetch('sloth_specs').fetch(0).fetch('labels')['owner'] = 'old-owner'
        File.write(managed_path, JSON.pretty_generate(existing))

        stdout, stderr, status = Open3.capture3(
          'ruby',
          "#{ROOT}/bin/rules-ctl",
          'diff',
          '--provider=sloth',
          "--output-dir=#{dir}",
          "--manifest=#{file.path}"
        )

        assert status.success?, stderr
        payload = JSON.parse(stdout).fetch(0)
        operation = payload.fetch('operations').fetch(0)
        assert_equal 'sloth', payload.fetch('provider')
        assert_equal 'diff', payload.fetch('mode')
        assert_equal 'update', operation.fetch('action')
        assert_includes operation.fetch('changes'), 'artifacts.sloth_specs[0].labels.owner'
      end
    end
  end

  def test_import_datadog_requires_credentials
    stdout, stderr, status = Open3.capture3(
      { 'DD_API_KEY' => nil, 'DD_APP_KEY' => nil },
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'import',
      '--provider=datadog',
      "#{ROOT}/examples/services/checkout.rb"
    )

    refute status.success?, stderr
    payload = JSON.parse(stdout)
    assert_equal false, payload.fetch('valid')
    assert_equal 'datadog', payload.fetch('provider')
    assert_equal 'missing_credentials', payload.fetch('error').fetch('code')
  end

  def test_import_manifest_bundle_reads_existing_manifest_file
    generate_stdout, generate_stderr, generate_status = Open3.capture3(
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'generate',
      '--provider=sloth',
      "#{ROOT}/examples/services/checkout.rb"
    )
    assert generate_status.success?, generate_stderr
    manifest = JSON.parse(generate_stdout).fetch(0)

    Dir.mktmpdir do |dir|
      manifest_path = File.join(dir, 'checkout-api', 'sloth', 'manifest.json')
      FileUtils.mkdir_p(File.dirname(manifest_path))
      File.write(manifest_path, JSON.pretty_generate(manifest))

      stdout, stderr, status = Open3.capture3(
        'ruby',
        "#{ROOT}/bin/rules-ctl",
        'import',
        '--provider=sloth',
        "--output-dir=#{dir}",
        "#{ROOT}/examples/services/checkout.rb"
      )

      assert status.success?, stderr
      payload = JSON.parse(stdout).fetch(0)
      assert_equal 'sloth', payload.fetch('provider')
      assert_equal 'import_existing', payload.fetch('mode')
      assert_equal 'manifest_file', payload.fetch('source')
      assert_equal 'checkout-api', payload.fetch('state').fetch('service')
      assert_equal [], payload.fetch('findings')
    end
  end

  def test_prune_confirm_requires_reviewed_manifest_input
    _stdout, stderr, status = Open3.capture3(
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'prune',
      '--provider=datadog',
      '--confirm',
      "#{ROOT}/examples/services/checkout.rb"
    )

    refute status.success?
    assert_includes stderr, 'live prune requires --manifest'
  end

  def test_prune_datadog_requires_credentials
    generate_stdout, generate_stderr, generate_status = Open3.capture3(
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'generate',
      '--provider=datadog',
      "#{ROOT}/examples/services/checkout.rb"
    )
    assert generate_status.success?, generate_stderr
    manifest = JSON.parse(generate_stdout).fetch(0)

    Tempfile.create(['datadog-prune-manifest', '.json']) do |file|
      file.write(JSON.generate(manifest))
      file.flush

      stdout, stderr, status = Open3.capture3(
        { 'DD_API_KEY' => nil, 'DD_APP_KEY' => nil },
        'ruby',
        "#{ROOT}/bin/rules-ctl",
        'prune',
        '--provider=datadog',
        "--manifest=#{file.path}"
      )

      refute status.success?, stderr
      payload = JSON.parse(stdout)
      assert_equal false, payload.fetch('valid')
      assert_equal 'datadog', payload.fetch('provider')
      assert_equal 'missing_credentials', payload.fetch('error').fetch('code')
    end
  end

  def test_prune_manifest_bundle_confirm_deletes_manifest_file
    generate_stdout, generate_stderr, generate_status = Open3.capture3(
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'generate',
      '--provider=sloth',
      "#{ROOT}/examples/services/checkout.rb"
    )
    assert generate_status.success?, generate_stderr
    manifest = JSON.parse(generate_stdout).fetch(0)

    Tempfile.create(['sloth-prune-manifest', '.json']) do |file|
      file.write(JSON.generate(manifest))
      file.flush

      Dir.mktmpdir do |dir|
        managed_path = File.join(dir, 'checkout-api', 'sloth', 'manifest.json')
        spec_path = File.join(dir, 'checkout-api', 'sloth', 'generated', 'sloth.yaml')
        FileUtils.mkdir_p(File.dirname(spec_path))
        File.write(managed_path, JSON.pretty_generate(manifest))
        File.write(spec_path, YAML.dump(manifest.fetch('artifacts').fetch('sloth_specs').fetch(0)))

        stdout, stderr, status = Open3.capture3(
          'ruby',
          "#{ROOT}/bin/rules-ctl",
          'prune',
          '--provider=sloth',
          '--confirm',
          "--output-dir=#{dir}",
          "--manifest=#{file.path}"
        )

        assert status.success?, stderr
        payload = JSON.parse(stdout).fetch(0)
        assert_equal 'sloth', payload.fetch('provider')
        assert_equal 'live', payload.fetch('mode')
        assert_equal %w[delete delete], payload.fetch('operations').map { |operation| operation.fetch('action') }
        refute File.exist?(managed_path), "expected #{managed_path} to be deleted"
        refute File.exist?(spec_path), "expected #{spec_path} to be deleted"
      end
    end
  end

  def test_prune_confirm_with_handoff_dir_blocks_stale_review_evidence
    generate_stdout, generate_stderr, generate_status = Open3.capture3(
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'generate',
      '--provider=sloth',
      "#{ROOT}/examples/services/checkout.rb"
    )
    assert generate_status.success?, generate_stderr
    manifest = with_review_provenance(JSON.parse(generate_stdout).fetch(0))

    Tempfile.create(['sloth-stale-prune-manifest', '.json']) do |file|
      file.write(JSON.generate(manifest))
      file.flush

      Dir.mktmpdir do |dir|
        managed_path = File.join(dir, 'checkout-api', 'sloth', 'manifest.json')
        FileUtils.mkdir_p(File.dirname(managed_path))
        File.write(managed_path, JSON.pretty_generate(manifest))

        handoff_dir = File.join(dir, 'handoff')
        FileUtils.mkdir_p(handoff_dir)
        File.write(
          File.join(handoff_dir, 'checkout-prod.handoff.json'),
          JSON.pretty_generate(
            label: 'checkout-prod',
            provider: 'datadog',
            review: {
              status: 'reviewed',
              accepted_candidate_uids: ['request-errors'],
              rejected_candidate_uids: ['request-latency'],
              notes: ['Errors accepted after review.']
            }
          )
        )

        stdout, stderr, status = Open3.capture3(
          'ruby',
          "#{ROOT}/bin/rules-ctl",
          'prune',
          '--provider=sloth',
          '--confirm',
          "--output-dir=#{dir}",
          "--manifest=#{file.path}",
          "--handoff-dir=#{handoff_dir}"
        )

        refute status.success?, stderr
        payload = JSON.parse(stdout)
        assert_equal 'invalid_manifest_review', payload.fetch('error').fetch('code')
        assert_equal 'stale_provenance', payload.fetch('manifest_review').fetch('manifests').fetch(0).fetch('status')
        assert File.exist?(managed_path), "expected stale review evidence not to delete #{managed_path}"
      end
    end
  end

  def test_prune_confirm_with_review_report_blocks_stale_saved_report
    generate_stdout, generate_stderr, generate_status = Open3.capture3(
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'generate',
      '--provider=sloth',
      "#{ROOT}/examples/services/checkout.rb"
    )
    assert generate_status.success?, generate_stderr
    current_manifest = with_review_provenance(JSON.parse(generate_stdout).fetch(0))
    current_manifest.fetch('review_provenance')['provider'] = 'sloth'
    old_manifest = Marshal.load(Marshal.dump(current_manifest))
    old_manifest.fetch('review_provenance')['accepted_candidate_uids'] = ['request-errors']

    Tempfile.create(['current-sloth-prune-manifest', '.json']) do |manifest_file|
      manifest_file.write(JSON.generate(current_manifest))
      manifest_file.flush

      Tempfile.create(['old-sloth-prune-manifest', '.json']) do |old_manifest_file|
        old_manifest_file.write(JSON.generate(old_manifest))
        old_manifest_file.flush

        Dir.mktmpdir do |dir|
          managed_path = File.join(dir, 'checkout-api', 'sloth', 'manifest.json')
          FileUtils.mkdir_p(File.dirname(managed_path))
          File.write(managed_path, JSON.pretty_generate(current_manifest))

          handoff_dir = File.join(dir, 'handoff')
          FileUtils.mkdir_p(handoff_dir)
          File.write(
            File.join(handoff_dir, 'checkout-prod.handoff.json'),
            JSON.pretty_generate(
              label: 'checkout-prod',
              provider: 'datadog',
              review: {
                status: 'reviewed',
                accepted_candidate_uids: ['request-latency'],
                rejected_candidate_uids: [],
                notes: ['Latency accepted.']
              }
            )
          )

          report_file = File.join(dir, 'old-manifest-review.json')
          _stdout, stderr, status = Open3.capture3(
            'ruby',
            "#{ROOT}/bin/rules-ctl",
            'manifest-review',
            '--provider=sloth',
            "--manifest=#{old_manifest_file.path}",
            "--output=#{report_file}"
          )
          assert status.success?, stderr

          stdout, _stderr, status = Open3.capture3(
            'ruby',
            "#{ROOT}/bin/rules-ctl",
            'prune',
            '--provider=sloth',
            '--confirm',
            "--output-dir=#{dir}",
            "--manifest=#{manifest_file.path}",
            "--handoff-dir=#{handoff_dir}",
            "--review-report=#{report_file}"
          )

          payload = JSON.parse(stdout)
          refute status.success?
          assert_equal 'stale_manifest_review_report', payload.fetch('error').fetch('code')
          assert_equal false, payload.fetch('saved_report').fetch('fresh')
          assert File.exist?(managed_path), "expected stale saved report not to delete #{managed_path}"
        end
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

  def test_discover_telemetry_scope_file_requires_output_dir
    Tempfile.create(['scopes', '.json']) do |file|
      file.write(JSON.generate([{ label: 'checkout-prod', service: 'checkout-api' }]))
      file.flush

      _stdout, stderr, status = Open3.capture3(
        'ruby',
        "#{ROOT}/bin/rules-ctl",
        'discover-telemetry',
        '--provider=prometheus_stack',
        "--scope-file=#{file.path}"
      )

      refute status.success?
      assert_includes stderr, 'missing --output-dir'
    end
  end

  def test_discover_telemetry_scope_file_rejects_single_scope_flags
    Tempfile.create(['scopes', '.json']) do |file|
      file.write(JSON.generate([{ label: 'checkout-prod', service: 'checkout-api' }]))
      file.flush

      _stdout, stderr, status = Open3.capture3(
        'ruby',
        "#{ROOT}/bin/rules-ctl",
        'discover-telemetry',
        '--provider=prometheus_stack',
        "--scope-file=#{file.path}",
        '--service=checkout-api',
        '--output-dir=/tmp/discovery'
      )

      refute status.success?
      assert_includes stderr, '--scope-file cannot be combined with --service, --selector, or --host'
    end
  end

  def test_discover_telemetry_scope_file_help_lists_batch_option
    stdout, stderr, status = Open3.capture3(
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'discover-telemetry',
      '--help'
    )

    assert status.success?, stderr
    assert_includes stdout, '--scope-file=FILE'
    assert_includes stdout, '--output-dir=DIR'
  end

  def test_onboarding_summary_ranks_saved_scope_results
    Dir.mktmpdir do |dir|
      File.write(
        File.join(dir, 'checkout-prod.json'),
        JSON.pretty_generate(
          provider: 'datadog',
          scope: { label: 'checkout-prod', service: 'checkout-api' },
          signals: [
            { kind: 'latency', metric: 'http.server.request.duration', user_visible: true, source: 'datadog' }
          ],
          findings: []
        )
      )
      File.write(
        File.join(dir, 'index.json'),
        JSON.pretty_generate(
          provider: 'datadog',
          generated_at: '2026-05-13T09:00:00Z',
          total_scopes: 1,
          successful_scopes: 1,
          failed_scopes: 0,
          scopes: [
            { label: 'checkout-prod', scope: { label: 'checkout-prod', service: 'checkout-api' }, status: 'ok', result_file: 'checkout-prod.json', signal_count: 1, finding_count: 0 }
          ]
        )
      )

      stdout, stderr, status = Open3.capture3(
        'ruby',
        "#{ROOT}/bin/rules-ctl",
        'onboarding-summary',
        File.join(dir, 'index.json')
      )

      assert status.success?, stderr
      payload = JSON.parse(stdout)
      assert_equal 'ready', payload.fetch('scopes').fetch(0).fetch('readiness')
    end
  end

  def test_onboarding_artifact_index_writes_saved_handoff_bundle_index
    Dir.mktmpdir do |dir|
      discovery_dir = File.join(dir, 'discovery')
      handoff_dir = File.join(dir, 'handoff')
      draft_dir = File.join(dir, 'drafts')
      manifest_dir = File.join(dir, 'generated')
      [discovery_dir, handoff_dir, draft_dir, manifest_dir].each { |path| FileUtils.mkdir_p(path) }

      File.write(
        File.join(discovery_dir, 'checkout-prod.json'),
        JSON.pretty_generate(
          provider: 'datadog',
          scope: { label: 'checkout-prod', service: 'checkout-api' },
          signals: [
            { kind: 'latency', metric: 'http.server.request.duration', user_visible: true, source: 'datadog' }
          ],
          findings: []
        )
      )
      index_path = File.join(discovery_dir, 'index.json')
      File.write(
        index_path,
        JSON.pretty_generate(
          provider: 'datadog',
          generated_at: '2026-05-13T09:00:00Z',
          total_scopes: 1,
          scopes: [
            { label: 'checkout-prod', scope: { label: 'checkout-prod', service: 'checkout-api' }, status: 'ok', result_file: 'checkout-prod.json', signal_count: 1, finding_count: 0 }
          ]
        )
      )
      File.write(
        File.join(handoff_dir, 'checkout-prod.handoff.json'),
        JSON.pretty_generate(
          label: 'checkout-prod',
          provider: 'datadog',
          review: {
            status: 'reviewed',
            accepted_candidate_uids: ['request-latency'],
            rejected_candidate_uids: [],
            notes: []
          }
        )
      )
      File.write(File.join(draft_dir, 'checkout-prod.rb'), "# reviewed draft\n")
      manifest_path = File.join(manifest_dir, 'checkout-api', 'datadog', 'manifest.json')
      FileUtils.mkdir_p(File.dirname(manifest_path))
      File.write(manifest_path, JSON.pretty_generate(service: 'checkout-api', provider: 'datadog', artifacts: {}))
      report_path = File.join(manifest_dir, 'manifest-review', 'datadog.json')
      FileUtils.mkdir_p(File.dirname(report_path))
      File.write(report_path, JSON.pretty_generate(valid: true))
      output_path = File.join(dir, 'handoff-index.json')

      stdout, stderr, status = Open3.capture3(
        'ruby',
        "#{ROOT}/bin/rules-ctl",
        'onboarding-artifact-index',
        "--handoff-dir=#{handoff_dir}",
        "--draft-dir=#{draft_dir}",
        "--manifest-dir=#{manifest_dir}",
        '--provider=datadog',
        "--output=#{output_path}",
        index_path
      )

      assert status.success?, stderr
      payload = JSON.parse(stdout)
      assert_equal payload, JSON.parse(File.read(output_path))
      assert_equal 1, payload.fetch('summary').fetch('complete_scopes')
      assert_equal 0, payload.fetch('summary').fetch('missing_artifact_count')
      provider = payload.fetch('scopes').fetch(0).fetch('providers').fetch(0)
      assert_equal manifest_path, provider.fetch('manifest').fetch('path')
      assert_equal report_path, provider.fetch('manifest_review_report').fetch('path')
      assert_includes provider.fetch('manifest_review_command'), '--report='
    end
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

  def test_model_report_command_outputs_review_provenance
    Tempfile.create(['reviewed-definition', '.rb']) do |file|
      file.write(<<~RUBY)
        require_relative '#{ROOT}/lib/sre'

        SRE.define do
          service 'checkout-api'
          owner 'payments-platform'
          review_provenance label: 'checkout-prod',
                            provider: 'datadog',
                            accepted_candidate_uids: ['request-latency'],
                            rejected_candidate_uids: ['request-traffic'],
                            notes: ['Latency accepted for rollout.']
        end
      RUBY
      file.flush

      stdout, stderr, status = Open3.capture3('ruby', "#{ROOT}/bin/rules-ctl", 'model-report', file.path)

      assert status.success?, stderr
      provenance = JSON.parse(stdout).fetch('review_provenance').fetch(0)
      assert_equal 'checkout-api', provenance.fetch('service')
      assert_equal 'payments-platform', provenance.fetch('owner')
      assert_equal 'checkout-prod', provenance.fetch('label')
      assert_equal ['request-latency'], provenance.fetch('accepted_candidate_uids')
      assert_equal ['request-traffic'], provenance.fetch('rejected_candidate_uids')
      assert_equal ['Latency accepted for rollout.'], provenance.fetch('notes')
    end
  end

end
