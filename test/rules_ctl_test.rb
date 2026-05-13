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

  def stub_singleton(receiver, method_name, replacement)
    original = receiver.method(method_name)
    receiver.define_singleton_method(method_name) { |*_args, **_kwargs, &_block| replacement }
    yield
  ensure
    receiver.define_singleton_method(method_name) do |*args, **kwargs, &block|
      original.call(*args, **kwargs, &block)
    end
  end

  def with_review_provenance(manifest)
    manifest.merge(
      review_provenance: {
        label: 'checkout-prod',
        provider: 'datadog',
        accepted_candidate_uids: ['request-latency'],
        notes: ['Latency accepted.']
      }
    )
  end

  def test_apply_renders_invalid_provider_payload_error
    load "#{ROOT}/examples/services/checkout.rb"
    definition = SloRulesEngine.definitions.fetch(0)
    manifest = with_review_provenance(SloRulesEngine.default_provider_registry.fetch('datadog')
      .generate(definition)
      .to_h
      .merge(service: definition.service))
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
          stub_singleton(SloRulesEngine::Appliers::Datadog, :new, fake_applier) do
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
    manifest = with_review_provenance(SloRulesEngine.default_provider_registry.fetch('datadog')
      .generate(definition)
      .to_h
      .merge(service: definition.service))
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
          stub_singleton(SloRulesEngine::Appliers::Datadog, :new, fake_applier) do
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
          stub_singleton(SloRulesEngine::Appliers::Datadog, :new, fake_applier) do
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
          stub_singleton(SloRulesEngine::TelemetryLookup::Prometheus, :new, fake_adapter) do
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
            stub_singleton(SloRulesEngine::TelemetryLookup::Datadog, :new, fake_adapter) do
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

  def test_onboarding_summary_writes_handoff_packets
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

      handoff_dir = File.join(dir, 'handoff')
      stdout, _stderr = capture_io do
        RulesCtl.onboarding_summary(['--handoff-dir', handoff_dir, File.join(dir, 'index.json')])
      end

      payload = JSON.parse(stdout)
      handoff_file = payload.fetch('scopes').fetch(0).fetch('handoff_file')
      assert_equal File.join(handoff_dir, 'checkout-prod.handoff.json'), handoff_file
      assert File.exist?(handoff_file), "expected #{handoff_file} to exist"
      packet = JSON.parse(File.read(handoff_file))
      assert_equal 'unreviewed', packet.fetch('review').fetch('status')
    end
  end

  def test_review_handoff_records_accepted_candidates
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'checkout-prod.handoff.json')
      File.write(path, JSON.pretty_generate(handoff_packet))

      stdout, _stderr = capture_io do
        RulesCtl.review_handoff([
          '--accept=request-latency',
          '--reject=request-traffic',
          '--note=Latency is ready for draft generation.',
          path
        ])
      end

      payload = JSON.parse(stdout)
      assert_equal 'reviewed', payload.fetch('review').fetch('status')
      assert_equal ['request-latency'], payload.fetch('review').fetch('accepted_candidate_uids')
      packet = JSON.parse(File.read(path))
      assert_equal ['request-traffic'], packet.fetch('review').fetch('rejected_candidate_uids')
    end
  end

  def test_review_handoff_rejects_unknown_candidate
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'checkout-prod.handoff.json')
      File.write(path, JSON.pretty_generate(handoff_packet))

      stdout, _stderr = capture_io do
        exit_error = assert_raises(SystemExit) do
          RulesCtl.review_handoff(['--accept=missing-sli', path])
        end
        assert_equal 1, exit_error.status
      end

      payload = JSON.parse(stdout)
      assert_equal false, payload.fetch('valid')
      assert_equal 'invalid_candidate_uid', payload.fetch('error').fetch('code')
      assert_equal 'unreviewed', JSON.parse(File.read(path)).fetch('review').fetch('status')
    end
  end

  def test_draft_from_handoff_outputs_accepted_candidate_draft
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'checkout-prod.handoff.json')
      File.write(path, JSON.pretty_generate(reviewed_handoff_packet))

      stdout, _stderr = capture_io do
        RulesCtl.draft_from_handoff([
          '--service=checkout-api',
          '--owner=payments-platform',
          path
        ])
      end

      assert_includes stdout, "uid 'request-latency'"
      refute_includes stdout, "uid 'request-traffic'"
      assert_includes stdout, '# handoff: checkout-prod provider=datadog'
      assert_includes stdout, '# review note: Latency is accepted for the first onboarding draft.'
    end
  end

  def test_draft_from_handoff_rejects_unreviewed_packet
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'checkout-prod.handoff.json')
      File.write(path, JSON.pretty_generate(handoff_packet))

      stdout, _stderr = capture_io do
        exit_error = assert_raises(SystemExit) do
          RulesCtl.draft_from_handoff([
            '--service=checkout-api',
            '--owner=payments-platform',
            path
          ])
        end
        assert_equal 1, exit_error.status
      end

      payload = JSON.parse(stdout)
      assert_equal false, payload.fetch('valid')
      assert_equal 'unreviewed_handoff', payload.fetch('error').fetch('code')
    end
  end

  def test_draft_from_handoff_rejects_invalid_reviewed_packet
    Dir.mktmpdir do |dir|
      packet = reviewed_handoff_packet
      packet.fetch(:candidate_review).fetch(:candidates).fetch(0).delete(:metric)
      path = File.join(dir, 'checkout-prod.handoff.json')
      File.write(path, JSON.pretty_generate(packet))

      stdout, _stderr = capture_io do
        exit_error = assert_raises(SystemExit) do
          RulesCtl.draft_from_handoff([
            '--service=checkout-api',
            '--owner=payments-platform',
            path
          ])
        end
        assert_equal 1, exit_error.status
      end

      payload = JSON.parse(stdout)
      assert_equal false, payload.fetch('valid')
      assert_equal 'invalid_handoff', payload.fetch('error').fetch('code')
      assert payload.fetch('errors').any? { |error| error.fetch('path') == 'candidate_review.candidates[0].metric' }
    end
  end

  def test_validate_handoff_reports_valid_reviewed_packet
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'checkout-prod.handoff.json')
      File.write(path, JSON.pretty_generate(reviewed_handoff_packet))

      stdout, _stderr = capture_io do
        RulesCtl.validate_handoff([path])
      end

      payload = JSON.parse(stdout)
      assert_equal true, payload.fetch('valid')
      assert_equal 1, payload.fetch('accepted_candidate_count')
    end
  end

  def test_validate_handoff_exits_one_for_invalid_packet
    Dir.mktmpdir do |dir|
      packet = reviewed_handoff_packet
      packet.fetch(:candidate_review).fetch(:candidates).fetch(0).delete(:metric)
      path = File.join(dir, 'checkout-prod.handoff.json')
      File.write(path, JSON.pretty_generate(packet))

      stdout, _stderr = capture_io do
        exit_error = assert_raises(SystemExit) do
          RulesCtl.validate_handoff([path])
        end
        assert_equal 1, exit_error.status
      end

      payload = JSON.parse(stdout)
      assert_equal false, payload.fetch('valid')
      assert payload.fetch('errors').any? { |error| error.fetch('path') == 'candidate_review.candidates[0].metric' }
    end
  end

  def handoff_packet
    {
      label: 'checkout-prod',
      provider: 'datadog',
      scope: { label: 'checkout-prod', service: 'checkout-api' },
      discovery: {
        signals: [{ kind: 'latency', metric: 'http.server.request.duration', user_visible: true }],
        findings: [],
        finding_codes: []
      },
      candidate_review: {
        candidates: [
          { sli_uid: 'request-latency', metric: 'http.server.request.duration', confidence: { level: 'high' } },
          { sli_uid: 'request-traffic', metric: 'http.server.requests', confidence: { level: 'medium' } }
        ],
        findings: []
      },
      review: {
        status: 'unreviewed',
        accepted_candidate_uids: [],
        rejected_candidate_uids: [],
        notes: []
      }
    }
  end

  def reviewed_handoff_packet
    packet = handoff_packet
    packet[:candidate_review] = {
      candidates: [
        handoff_candidate(
          sli_uid: 'request-latency',
          signal: 'latency',
          metric: 'http.server.request.duration',
          slo_uid: 'fast-enough'
        ),
        handoff_candidate(
          sli_uid: 'request-traffic',
          signal: 'traffic',
          metric: 'http.server.requests',
          slo_uid: 'healthy-enough'
        )
      ],
      findings: []
    }
    packet[:review] = {
      status: 'reviewed',
      accepted_candidate_uids: ['request-latency'],
      rejected_candidate_uids: ['request-traffic'],
      notes: ['Latency is accepted for the first onboarding draft.']
    }
    packet
  end

  def handoff_candidate(sli_uid:, signal:, metric:, slo_uid:)
    {
      sli_uid: sli_uid,
      signal: signal,
      metric: metric,
      rationale: 'Measured telemetry is close to user-visible service quality.',
      confidence: { level: 'high', score: 85, reasons: [], caveats: [] },
      explanation: "Metric #{metric} is proposed as #{sli_uid}.",
      evidence: { source: 'datadog' },
      calculation_basis_recommendation: nil,
      proposed_slo: {
        uid: slo_uid,
        objective: 0.99,
        success_condition: 'Observation meets the reviewed service quality threshold.',
        calculation_basis: 'observations'
      }
    }
  end
end
