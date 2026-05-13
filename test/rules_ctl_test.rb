# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'tempfile'
load File.expand_path('../bin/rules-ctl', __dir__)

class RulesCtlTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def setup
    SloRulesEngine.clear_definitions
  end

  def test_apply_renders_invalid_provider_payload_error
    load "#{ROOT}/examples/services/checkout.rb"
    definition = SloRulesEngine.definitions.fetch(0)
    manifest = SloRulesEngine.default_provider_registry.fetch('datadog')
      .generate(definition)
      .to_h
      .merge(service: definition.service)
    result = SloRulesEngine::ValidationResult.new
    result.error('query', 'contains unresolved SLO reference')
    payload_error = SloRulesEngine::Datadog::PayloadError.new(
      target: 'datadog.monitor',
      payload: { query: '__SLO_REF__[missing]' },
      result: result
    )
    fake_applier = Object.new
    fake_applier.define_singleton_method(:apply) { |_reviewed_manifest| raise payload_error }

    Tempfile.create(['reviewed-manifest', '.json']) do |file|
      file.write(JSON.generate(manifest))
      file.flush

      stdout, _stderr = capture_io do
        exit_error = assert_raises(SystemExit) do
          SloRulesEngine::Appliers::Datadog.stub(:new, fake_applier) do
            RulesCtl.apply(['--provider=datadog', '--confirm', "--manifest=#{file.path}"])
          end
        end
        assert_equal 1, exit_error.status
      end

      payload = JSON.parse(stdout)
      assert_equal false, payload.fetch('valid')
      assert_equal 'datadog', payload.fetch('provider')
      assert_equal 'live', payload.fetch('mode')
      assert_equal 'invalid_provider_payload', payload.fetch('error').fetch('code')
      assert_equal 'query', payload.fetch('errors').fetch(0).fetch('path')
    end
  end

  def test_apply_renders_unsafe_provider_state_error
    load "#{ROOT}/examples/services/checkout.rb"
    definition = SloRulesEngine.definitions.fetch(0)
    manifest = SloRulesEngine.default_provider_registry.fetch('datadog')
      .generate(definition)
      .to_h
      .merge(service: definition.service)
    operation = SloRulesEngine::ApplyOperation.new(
      action: 'update',
      target: 'datadog.slo',
      name: 'checkout-api http-requests public-api successful-requests',
      source: 'artifacts.slos[0]',
      match_identity: { strategy: 'name', confidence: 'medium' }
    )
    result = SloRulesEngine::ValidationResult.new
    result.error('match_identity', 'live Datadog mutation requires managed source_ref identity for update operations')
    ownership_error = SloRulesEngine::Datadog::OwnershipError.new(operation: operation, result: result)
    fake_applier = Object.new
    fake_applier.define_singleton_method(:apply) { |_reviewed_manifest| raise ownership_error }

    Tempfile.create(['reviewed-manifest', '.json']) do |file|
      file.write(JSON.generate(manifest))
      file.flush

      stdout, _stderr = capture_io do
        exit_error = assert_raises(SystemExit) do
          SloRulesEngine::Appliers::Datadog.stub(:new, fake_applier) do
            RulesCtl.apply(['--provider=datadog', '--confirm', "--manifest=#{file.path}"])
          end
        end
        assert_equal 1, exit_error.status
      end

      payload = JSON.parse(stdout)
      assert_equal false, payload.fetch('valid')
      assert_equal 'datadog', payload.fetch('provider')
      assert_equal 'live', payload.fetch('mode')
      assert_equal 'unsafe_provider_state', payload.fetch('error').fetch('code')
      assert_equal 'match_identity', payload.fetch('errors').fetch(0).fetch('path')
    end
  end

  def test_prune_renders_unsafe_provider_state_error
    load "#{ROOT}/examples/services/checkout.rb"
    definition = SloRulesEngine.definitions.fetch(0)
    manifest = SloRulesEngine.default_provider_registry.fetch('datadog')
      .generate(definition)
      .to_h
      .merge(service: definition.service)
    operation = SloRulesEngine::ApplyOperation.new(
      action: 'delete',
      target: 'datadog.monitor',
      name: 'orphan monitor',
      source: 'managed_state.monitors[2]',
      match_identity: { strategy: 'service_scope_only', confidence: 'low' }
    )
    result = SloRulesEngine::ValidationResult.new
    result.error('match_identity', 'live Datadog mutation requires managed source_ref identity for delete operations')
    ownership_error = SloRulesEngine::Datadog::OwnershipError.new(operation: operation, result: result)
    fake_applier = Object.new
    fake_applier.define_singleton_method(:prune) { |_reviewed_manifest, mode:| raise ownership_error if mode == 'live' }

    Tempfile.create(['reviewed-manifest', '.json']) do |file|
      file.write(JSON.generate(manifest))
      file.flush

      stdout, _stderr = capture_io do
        exit_error = assert_raises(SystemExit) do
          SloRulesEngine::Appliers::Datadog.stub(:new, fake_applier) do
            RulesCtl.prune(['--provider=datadog', '--confirm', "--manifest=#{file.path}"])
          end
        end
        assert_equal 1, exit_error.status
      end

      payload = JSON.parse(stdout)
      assert_equal false, payload.fetch('valid')
      assert_equal 'datadog', payload.fetch('provider')
      assert_equal 'live', payload.fetch('mode')
      assert_equal 'unsafe_provider_state', payload.fetch('error').fetch('code')
      assert_equal 'match_identity', payload.fetch('errors').fetch(0).fetch('path')
    end
  end

  def test_discover_telemetry_scope_file_writes_index_and_exits_zero_when_all_scopes_succeed
    fake_adapter = Object.new
    fake_adapter.define_singleton_method(:discover) do |service: nil, selectors: {}, host: nil|
      SloRulesEngine::TelemetryLookup::Result.new(
        provider: 'prometheus_stack',
        signals: [
          SloRulesEngine::TelemetryLookup.discovered_signal(
            metric: "metric.for.#{service || selectors.fetch('team')}",
            source: 'prometheus'
          )
        ],
        findings: []
      )
    end

    Tempfile.create(['scopes', '.json']) do |file|
      file.write(JSON.generate([
        { label: 'checkout-prod', service: 'checkout-api' },
        { label: 'payments-prod', selectors: { team: 'payments' } }
      ]))
      file.flush

      Dir.mktmpdir do |dir|
        stdout, _stderr = capture_io do
          SloRulesEngine::TelemetryLookup::Prometheus.stub(:new, fake_adapter) do
            RulesCtl.discover_telemetry([
              '--provider=prometheus_stack',
              "--scope-file=#{file.path}",
              "--output-dir=#{dir}"
            ])
          end
        end

        payload = JSON.parse(stdout)
        assert_equal 'prometheus_stack', payload.fetch('provider')
        assert_equal 2, payload.fetch('successful_scopes')
        assert_equal 0, payload.fetch('failed_scopes')
        assert File.exist?(File.join(dir, 'index.json'))
      end
    end
  end

  def test_discover_telemetry_scope_file_records_failed_scopes_and_exits_one
    fake_adapter = Object.new
    fake_adapter.define_singleton_method(:discover) do |service: nil, selectors: {}, host: nil|
      if service == 'checkout-api'
        SloRulesEngine::TelemetryLookup::Result.new(
          provider: 'datadog',
          signals: [SloRulesEngine::TelemetryLookup.discovered_signal(metric: 'http.server.request.duration', source: 'datadog')],
          findings: []
        )
      else
        raise 'backend query failed'
      end
    end

    Tempfile.create(['scopes', '.json']) do |file|
      file.write(JSON.generate([
        { label: 'checkout-prod', service: 'checkout-api' },
        { label: 'payments-prod', selectors: { team: 'payments' } }
      ]))
      file.flush

      Dir.mktmpdir do |dir|
        stdout, _stderr = capture_io do
          exit_error = assert_raises(SystemExit) do
            SloRulesEngine::TelemetryLookup::Datadog.stub(:new, fake_adapter) do
              RulesCtl.discover_telemetry([
                '--provider=datadog',
                "--scope-file=#{file.path}",
                "--output-dir=#{dir}"
              ])
            end
          end
          assert_equal 1, exit_error.status
        end

        payload = JSON.parse(stdout)
        assert_equal 1, payload.fetch('successful_scopes')
        assert_equal 1, payload.fetch('failed_scopes')
        failed_scope = payload.fetch('scopes').find { |entry| entry.fetch('status') == 'error' }
        assert_equal 'discovery_failed', failed_scope.fetch('error').fetch('code')
      end
    end
  end

  def test_onboarding_summary_renders_ranked_scope_queue
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

      stdout, _stderr = capture_io do
        RulesCtl.onboarding_summary([File.join(dir, 'index.json')])
      end

      payload = JSON.parse(stdout)
      assert_equal 'datadog', payload.fetch('provider')
      assert_equal 'checkout-prod', payload.fetch('scopes').fetch(0).fetch('label')
      assert_equal 'ready', payload.fetch('scopes').fetch(0).fetch('readiness')
    end
  end
end
