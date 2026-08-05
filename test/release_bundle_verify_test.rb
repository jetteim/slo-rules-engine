# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'tmpdir'
require_relative 'support/release_bundle_fixtures'

class ReleaseBundleVerifyTest < Minitest::Test
  include ReleaseBundleFixtures

  REVIEWER = 'team/payments-sre'
  REVIEWED_AT = '2026-07-27T09:30:00Z'
  VERIFIED_AT = '2026-07-29T10:15:00.000000Z'

  class FakePrometheusClient
    attr_reader :queries

    def initialize(now:, empty: false, burn_rate: 0.2)
      @now = now
      @empty = empty
      @burn_rate = burn_rate
      @queries = []
    end

    def query(expression)
      queries << expression
      return { 'resultType' => 'vector', 'result' => [] } if @empty

      value =
        if expression.start_with?('timestamp(')
          (@now - 10).to_f
        elsif expression.start_with?('slo:period_error_budget_remaining:ratio')
          0.8
        elsif expression.start_with?('slo:error_budget:ratio')
          0.001
        elsif expression.start_with?('slo:objective:ratio')
          0.999
        elsif expression.start_with?('1 - (slo:sli_error:ratio_rate')
          0.9998
        elsif expression.start_with?('slo:current_burn_rate:ratio') ||
              expression.start_with?('slo:period_burn_rate:ratio')
          @burn_rate
        elsif expression.start_with?('sum(rate(')
          42
        else
          raise "unexpected query #{expression.inspect}"
        end
      {
        'resultType' => 'vector',
        'result' => [{ 'metric' => {}, 'value' => [@now.to_f, value.to_s] }]
      }
    end
  end

  def test_verifies_every_file_target_without_mutation_and_builds_an_immutable_successor
    Dir.mktmpdir do |dir|
      applied, managed_dir, journal_dir = applied_bundle(dir)
      predecessor = Marshal.load(Marshal.dump(applied))
      journal_bytes = journal_files(journal_dir).to_h { |path| [path, File.binread(path)] }
      managed_mtimes = managed_files(managed_dir).to_h { |path| [path, File.mtime(path)] }
      verifier = RecordingVerifier.new

      verified = SloRulesEngine::ReleaseBundle::Verifier.new(
        verifier: verifier,
        clock: -> { Time.iso8601(VERIFIED_AT) }
      ).verify(applied)

      assert_equal applied.fetch(:targets).map { |target| target.fetch(:uid) }.sort,
                   verifier.target_uids.uniq
      assert_equal 'verified', verified.fetch(:lifecycle)
      assert_equal(
        {
          action: 'verify',
          predecessor_bundle_id: applied.fetch(:bundle_id),
          predecessor_lifecycle: 'applied'
        },
        verified.fetch(:transition)
      )
      assert_equal 2, verified.fetch(:summary).fetch(:verification_count)
      assert_equal({ 'succeeded' => 2 }, verified.fetch(:summary).fetch(:verifications_by_status))
      assert_equal predecessor, applied
      assert_equal managed_mtimes, managed_files(managed_dir).to_h { |path| [path, File.mtime(path)] }
      assert_equal journal_bytes, journal_files(journal_dir).to_h { |path| [path, File.binread(path)] }
      refute_equal applied.fetch(:bundle_id), verified.fetch(:bundle_id)
      assert SloRulesEngine::ReleaseBundle::SchemaValidator.validate(verified).valid?
      assert_equal 'verified',
                   SloRulesEngine::ReleaseBundle::StatusEvaluator.new.evaluate(verified)
                     .fetch(:effective_lifecycle)

      contents = verification_contents(verified)
      prometheus = contents.fetch('checkout-api/prometheus_stack')
      assert_equal 'succeeded', prometheus.fetch(:status)
      assert_equal 'succeeded', prometheus.fetch(:verification).fetch(:status)
      assert_equal 'not_required', prometheus.fetch(:verification).fetch(:external_status)

      sloth = contents.fetch('checkout-api/sloth')
      assert_equal 'succeeded', sloth.fetch(:status)
      assert_equal 'pending', sloth.fetch(:verification).fetch(:status)
      assert_equal 'succeeded', sloth.fetch(:verification).fetch(:engine_owned_status)
      assert_equal 'pending', sloth.fetch(:verification).fetch(:external_status)
      assert_includes sloth.fetch(:verification).fetch(:requirements),
                      'confirm_external_generator_completion'
    end
  end

  def test_fails_without_a_successor_when_an_engine_owned_file_drifted
    Dir.mktmpdir do |dir|
      applied, managed_dir, = applied_bundle(dir)
      path = File.join(managed_dir, 'checkout-api', 'prometheus_stack', 'manifest.json')
      manifest = JSON.parse(File.read(path))
      manifest['drift'] = true
      File.write(path, JSON.pretty_generate(manifest))

      error = assert_raises(SloRulesEngine::ReleaseBundle::VerifyError) do
        SloRulesEngine::ReleaseBundle::Verifier.new(
          clock: -> { Time.iso8601(VERIFIED_AT) }
        ).verify(applied)
      end

      assert_equal 'bundle_target_verification_failed', error.code
      assert_equal 'checkout-api/prometheus_stack', error.target_uid
      assert_includes error.findings.map { |finding| finding.fetch(:code) },
                      'managed_file_content_mismatch'
    end
  end

  def test_packages_evidence_and_completes_sloth_downstream_verification_from_live_status
    Dir.mktmpdir do |dir|
      applied, managed_dir, journal_dir, fixture = applied_bundle(dir)
      evidence = write_sloth_downstream_evidence_fixture(
        dir,
        fixture.fetch(:manifests).fetch('sloth')
      )
      predecessor = Marshal.load(Marshal.dump(applied))
      managed_mtimes = managed_files(managed_dir).to_h { |path| [path, File.mtime(path)] }
      journal_bytes = journal_files(journal_dir).to_h { |path| [path, File.binread(path)] }
      clients = []
      now = Time.iso8601(VERIFIED_AT)

      verified = SloRulesEngine::ReleaseBundle::Verifier.new(
        live_status_client_factory: lambda do |base_url|
          clients << [base_url, FakePrometheusClient.new(now: now)]
          clients.last.fetch(1)
        end,
        clock: -> { now }
      ).verify(
        applied,
        sloth_evidence: { 'checkout-api/sloth' => evidence.fetch(:evidence) },
        target_base_urls: { 'checkout-api/sloth' => 'https://prometheus.example.test' },
        max_age_seconds: 300
      )

      assert_equal predecessor, applied
      assert_equal managed_mtimes, managed_files(managed_dir).to_h { |path| [path, File.mtime(path)] }
      assert_equal journal_bytes, journal_files(journal_dir).to_h { |path| [path, File.binread(path)] }
      sloth_target = verified.fetch(:targets).find { |target| target.fetch(:provider) == 'sloth' }
      evidence_artifact = verified.fetch(:artifacts).find do |artifact|
        artifact.fetch(:uid) == sloth_target.fetch(:downstream_evidence_artifact_uid)
      end
      assert_equal 'sloth_downstream_evidence', evidence_artifact.fetch(:kind)
      assert_equal evidence.fetch(:evidence), evidence_artifact.dig(:source, :path)

      sloth = verification_contents(verified).fetch('checkout-api/sloth')
      assert_equal 'succeeded', sloth.dig(:verification, :status)
      assert_equal 'succeeded', sloth.dig(:verification, :external_status)
      external = sloth.dig(:verification, :resources).find { |resource| resource.fetch(:ownership) == 'external' }
      assert_equal 'succeeded', external.fetch(:status)
      assert_equal 'sloth', external.dig(:live_status_report, :provider)
      assert_equal 'healthy', external.dig(:live_status_report, :statuses, 0, :state)
      assert_equal(
        SloRulesEngine::ProviderState::Value.fetch(evidence_artifact.fetch(:content), :evidence_id),
        external.fetch(:evidence_id)
      )
      assert_equal 1, clients.length
      assert_equal 'https://prometheus.example.test', clients.fetch(0).fetch(0)
      assert_equal 8, clients.fetch(0).fetch(1).queries.length
      refute_includes JSON.generate(verified), 'prometheus.example.test'
    end
  end

  def test_rejects_stale_sloth_evidence_before_managed_reads_or_client_construction
    Dir.mktmpdir do |dir|
      applied, _managed_dir, _journal_dir, fixture = applied_bundle(dir)
      evidence = write_sloth_downstream_evidence_fixture(
        dir,
        fixture.fetch(:manifests).fetch('sloth')
      )
      generated = YAML.safe_load(File.read(evidence.fetch(:generated)), aliases: false)
      generated.fetch('groups').fetch(0).fetch('rules').fetch(0)['expr'] = 'vector(0)'
      File.write(evidence.fetch(:generated), YAML.dump(generated))
      managed_verifier = RecordingVerifier.new
      client_count = 0

      error = assert_raises(SloRulesEngine::ReleaseBundle::VerifyError) do
        SloRulesEngine::ReleaseBundle::Verifier.new(
          verifier: managed_verifier,
          live_status_client_factory: lambda do |_base_url|
            client_count += 1
            FakePrometheusClient.new(now: Time.iso8601(VERIFIED_AT))
          end
        ).verify(
          applied,
          sloth_evidence: { 'checkout-api/sloth' => evidence.fetch(:evidence) },
          target_base_urls: { 'checkout-api/sloth' => 'https://prometheus.example.test' }
        )
      end

      assert_equal 'invalid_sloth_bundle_verification_evidence', error.code
      assert_includes error.findings.map { |finding| finding.fetch(:code) }, 'stale_generated_rules'
      assert_empty managed_verifier.target_uids
      assert_equal 0, client_count
    end
  end

  def test_rejects_incomplete_sloth_runtime_mapping_before_managed_reads_or_clients
    Dir.mktmpdir do |dir|
      applied, _managed_dir, _journal_dir, fixture = applied_bundle(dir)
      evidence = write_sloth_downstream_evidence_fixture(
        dir,
        fixture.fetch(:manifests).fetch('sloth')
      )
      managed_verifier = RecordingVerifier.new
      client_count = 0

      error = assert_raises(SloRulesEngine::ReleaseBundle::VerifyError) do
        SloRulesEngine::ReleaseBundle::Verifier.new(
          verifier: managed_verifier,
          live_status_client_factory: ->(_base_url) { client_count += 1 }
        ).verify(
          applied,
          sloth_evidence: { 'checkout-api/sloth' => evidence.fetch(:evidence) },
          target_base_urls: {}
        )
      end

      assert_equal 'missing_sloth_bundle_verification_runtime', error.code
      assert_empty managed_verifier.target_uids
      assert_equal 0, client_count

      error = assert_raises(SloRulesEngine::ReleaseBundle::VerifyError) do
        SloRulesEngine::ReleaseBundle::Verifier.new(
          verifier: managed_verifier,
          live_status_client_factory: ->(_base_url) { client_count += 1 }
        ).verify(
          applied,
          sloth_evidence: { 'checkout-api/sloth' => evidence.fetch(:evidence) },
          target_base_urls: {
            'checkout-api/sloth' => 'https://user:secret@prometheus.example.test'
          }
        )
      end
      assert_equal 'invalid_sloth_bundle_verification_runtime', error.code
      assert_empty managed_verifier.target_uids
      assert_equal 0, client_count
    end
  end

  def test_accepts_at_risk_live_status_as_converged_downstream_provider_state
    Dir.mktmpdir do |dir|
      applied, _managed_dir, _journal_dir, fixture = applied_bundle(dir)
      evidence = write_sloth_downstream_evidence_fixture(
        dir,
        fixture.fetch(:manifests).fetch('sloth')
      )
      now = Time.iso8601(VERIFIED_AT)

      verified = SloRulesEngine::ReleaseBundle::Verifier.new(
        live_status_client_factory: lambda do |_base_url|
          FakePrometheusClient.new(now: now, burn_rate: 2.0)
        end,
        clock: -> { now }
      ).verify(
        applied,
        sloth_evidence: { 'checkout-api/sloth' => evidence.fetch(:evidence) },
        target_base_urls: { 'checkout-api/sloth' => 'https://prometheus.example.test' }
      )

      sloth = verification_contents(verified).fetch('checkout-api/sloth')
      external = sloth.dig(:verification, :resources).find { |resource| resource.fetch(:ownership) == 'external' }
      assert_equal 'succeeded', external.fetch(:status)
      assert_equal 'at_risk', external.dig(:live_status_report, :statuses, 0, :state)
      assert_equal 'succeeded', sloth.dig(:verification, :external_status)
    end
  end

  def test_preserves_packaged_evidence_as_pending_without_an_explicit_runtime
    Dir.mktmpdir do |dir|
      applied, = applied_bundle(dir, package_sloth_evidence: true)

      verified = SloRulesEngine::ReleaseBundle::Verifier.new(
        live_status_client_factory: ->(_base_url) { raise 'must not construct a client' },
        clock: -> { Time.iso8601(VERIFIED_AT) }
      ).verify(applied)

      sloth_target = verified.fetch(:targets).find { |target| target.fetch(:provider) == 'sloth' }
      assert sloth_target.fetch(:downstream_evidence_artifact_uid)
      sloth = verification_contents(verified).fetch('checkout-api/sloth')
      assert_equal 'pending', sloth.dig(:verification, :external_status)
      assert_equal 'pending', sloth.dig(:verification, :status)
    end
  end

  def test_fails_downstream_verification_when_live_bindings_have_no_telemetry
    Dir.mktmpdir do |dir|
      applied, _managed_dir, _journal_dir, fixture = applied_bundle(dir)
      evidence = write_sloth_downstream_evidence_fixture(
        dir,
        fixture.fetch(:manifests).fetch('sloth')
      )

      error = assert_raises(SloRulesEngine::ReleaseBundle::VerifyError) do
        SloRulesEngine::ReleaseBundle::Verifier.new(
          live_status_client_factory: lambda do |_base_url|
            FakePrometheusClient.new(now: Time.iso8601(VERIFIED_AT), empty: true)
          end,
          clock: -> { Time.iso8601(VERIFIED_AT) }
        ).verify(
          applied,
          sloth_evidence: { 'checkout-api/sloth' => evidence.fetch(:evidence) },
          target_base_urls: { 'checkout-api/sloth' => 'https://prometheus.example.test' }
        )
      end

      assert_equal 'bundle_target_verification_failed', error.code
      assert_equal 'checkout-api/sloth', error.target_uid
      assert_includes error.findings.map { |finding| finding.fetch(:code) },
                      'sloth_downstream_live_status_incomplete'
    end
  end

  def test_rejects_live_or_mixed_targets_before_any_managed_file_read
    Dir.mktmpdir do |dir|
      applied, = applied_bundle(dir)
      mixed = Marshal.load(Marshal.dump(applied))
      mixed.fetch(:targets).last[:automation_mode] = 'live_api'
      mixed[:bundle_id] = SloRulesEngine::ReleaseBundle::Fingerprint.bundle_id(mixed)
      verifier = RecordingVerifier.new

      error = assert_raises(SloRulesEngine::ReleaseBundle::VerifyError) do
        SloRulesEngine::ReleaseBundle::Verifier.new(verifier: verifier).verify(mixed)
      end

      assert_equal 'unsupported_bundle_verify_target', error.code
      assert_empty verifier.target_uids
    end
  end

  def test_rejects_invalid_journal_evidence_before_any_managed_file_read
    Dir.mktmpdir do |dir|
      applied, _managed_dir, = applied_bundle(dir)
      execution = applied.fetch(:artifacts).find do |artifact|
        artifact.fetch(:kind) == 'execution_result'
      end.fetch(:content)
      journal_path = execution.fetch(:operation_journal).fetch(:path)
      journal = JSON.parse(File.read(journal_path))
      journal['status'] = 'partial'
      File.write(journal_path, JSON.pretty_generate(journal))
      verifier = RecordingVerifier.new

      error = assert_raises(SloRulesEngine::ReleaseBundle::VerifyError) do
        SloRulesEngine::ReleaseBundle::Verifier.new(verifier: verifier).verify(applied)
      end

      assert_equal 'invalid_bundle_verification_inputs', error.code
      assert_empty verifier.target_uids
      assert_includes error.findings.map { |finding| finding.fetch(:code) },
                      'invalid_operation_journal'
    end
  end

  private

  def applied_bundle(dir, package_sloth_evidence: false)
    fixture = write_release_bundle_fixture(
      dir,
      providers: %w[prometheus_stack sloth]
    )
    sloth_evidence = if package_sloth_evidence
                       evidence = write_sloth_downstream_evidence_fixture(
                         dir,
                         fixture.fetch(:manifests).fetch('sloth')
                       )
                       { 'checkout-api/sloth' => evidence.fetch(:evidence) }
                     else
                       {}
                     end
    review_ready = SloRulesEngine::ReleaseBundle::Builder.new.build(
      fixture.fetch(:artifact_index),
      reviewer: REVIEWER,
      reviewed_at: REVIEWED_AT,
      sloth_evidence: sloth_evidence
    )
    managed_dir = File.join(dir, 'managed')
    runtime = fixture.fetch(:targets).to_h do |target_uid|
      [target_uid, { output_dir: managed_dir }]
    end
    apply_ready = SloRulesEngine::ReleaseBundle::Planner.new.plan(
      review_ready,
      target_runtime: runtime
    )
    documents = fixture.fetch(:targets).map do |target_uid|
      payload = SloRulesEngine::ProviderState::ApprovedPlan::Builder.new.build(
        apply_ready,
        target_uid: target_uid,
        reviewer: REVIEWER,
        reviewed_at: REVIEWED_AT
      )
      SloRulesEngine::ProviderState::ApprovedPlan::Loader.new.load(payload)
    end
    journal_dir = File.join(dir, 'journals')
    applied = SloRulesEngine::ReleaseBundle::Applier.new(
      executor: SloRulesEngine::ProviderState::ExactPlanExecutor.new(
        journal_dir: journal_dir,
        clock: -> { Time.iso8601(REVIEWED_AT) }
      )
    ).apply(apply_ready, approved_plans: documents)
    [applied, managed_dir, journal_dir, fixture]
  end

  def verification_contents(bundle)
    bundle.fetch(:artifacts).filter_map do |artifact|
      next unless artifact.fetch(:kind) == 'target_verification'

      content = artifact.fetch(:content)
      [content.fetch(:target_uid), content]
    end.to_h
  end

  def managed_files(root)
    Dir.glob(File.join(root, '**', '*')).select { |path| File.file?(path) }.sort
  end

  def journal_files(root)
    Dir.glob(File.join(root, '**', '*.json')).sort
  end

  class RecordingVerifier
    attr_reader :target_uids

    def initialize
      @delegate = SloRulesEngine::ProviderState::ManagedFileVerifier.new
      @target_uids = []
    end

    def verify(entry, checked_at:)
      @target_uids << target_uid(entry)
      @delegate.verify(entry, checked_at: checked_at)
    end

    private

    def target_uid(entry)
      path = SloRulesEngine::ProviderState::Value.fetch(
        SloRulesEngine::ProviderState::Value.fetch(entry, :desired),
        :path
      )
      %w[prometheus_stack sloth].filter_map do |provider|
        "checkout-api/#{provider}" if path.to_s.include?("/#{provider}/")
      end.fetch(0)
    end
  end
end
