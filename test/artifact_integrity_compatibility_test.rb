# frozen_string_literal: true

require 'minitest/autorun'
require 'digest'
require 'open3'
require 'rbconfig'
require_relative '../lib/slo_rules_engine'
require_relative 'support/release_bundle_fixtures'

# Golden results were captured from 18d0879 before shared-policy extraction.
# Synthetic identity inputs exercise assembly policies, not schema validity.
class ArtifactIntegrityCompatibilityTest < Minitest::Test
  include ReleaseBundleFixtures

  GOLDEN_PATH = File.join(__dir__, 'fixtures/artifact-integrity/identities.json')
  VECTORS = [
    [nil, 'null'],
    [{}, '{}'],
    [[], '[]'],
    ['checkout', '"checkout"'],
    [{ z: 2, a: { y: [:healthy, nil], x: true } }, '{"a":{"x":true,"y":["healthy",null]},"z":2}'],
    [{ 'b' => 2, 'a' => 1 }, '{"a":1,"b":2}'],
    [[{ z: 1, a: 2 }, 0.5, false], '[{"a":2,"z":1},0.5,false]'],
    [{ a: 1, 'a' => 2 }, '{"a":2}'],
    [{ 'a' => 2, a: 1 }, '{"a":1}'],
    [{ 'message' => "café\ncheckout" }, '{"message":"café\\ncheckout"}']
  ].freeze

  def test_canonical_json_bytes_and_hashes_are_preserved
    VECTORS.each do |input, bytes|
      expected = Digest::SHA256.hexdigest(bytes)
      assert_equal expected, SloRulesEngine::ProviderState::Fingerprint.content(input)
      assert_equal expected, SloRulesEngine::ReleaseBundle::Fingerprint.content(input)
      assert_equal expected, review_support.send(:fingerprint, input)
      assert_equal "sha256:#{expected}", onboarding_support.send(:fingerprint, input)
      [SloRulesEngine::ProviderState::Fingerprint, SloRulesEngine::ReleaseBundle::Fingerprint,
       review_support, onboarding_support].each do |owner|
        assert_equal bytes, JSON.generate(owner.send(:canonicalize, input))
      end
    end
  end

  def test_canonicalization_does_not_change_input_or_array_order
    input = { z: [3, { b: 2, a: 1 }, 1], a: :healthy }
    original = Marshal.dump(input)
    assert_equal({ 'a' => :healthy, 'z' => [3, { 'a' => 1, 'b' => 2 }, 1] },
                 SloRulesEngine::ProviderState::Fingerprint.canonicalize(input))
    assert_equal original, Marshal.dump(input)
  end

  def test_onboarding_preserves_fetch_semantics_for_hash_subclasses
    lookup_hash = Class.new(Hash) do
      def [](_key)
        'bracket-read'
      end
    end.new
    lookup_hash[:a] = 'stored-value'
    assert_equal({ 'a' => 'bracket-read' }, SloRulesEngine::ProviderState::Fingerprint.canonicalize(lookup_hash))
    assert_equal({ 'a' => 'bracket-read' }, SloRulesEngine::ReleaseBundle::Fingerprint.canonicalize(lookup_hash))
    assert_equal({ 'a' => 'bracket-read' }, review_support.send(:canonicalize, lookup_hash))
    assert_equal({ 'a' => 'stored-value' }, onboarding_support.send(:canonicalize, lookup_hash))
    assert_equal "sha256:#{Digest::SHA256.hexdigest('{"a":"stored-value"}')}",
                 onboarding_support.send(:fingerprint, lookup_hash)
  end

  def test_text_hashing_is_distinct_from_json_string_hashing
    fingerprint = SloRulesEngine::ReleaseBundle::Fingerprint
    assert_equal Digest::SHA256.hexdigest('checkout'), fingerprint.text('checkout')
    refute_equal fingerprint.text('checkout'), fingerprint.content('checkout')
    assert_equal fingerprint.text("# public fixture\n"),
                 fingerprint.artifact_content(content_type: 'text/x-ruby', content: "# public fixture\n")
    assert_equal fingerprint.content(a: 1),
                 fingerprint.artifact_content(content_type: 'application/json', content: { a: 1 })
  end

  def test_only_onboarding_falls_back_on_json_generator_errors
    [Float::NAN, Float::INFINITY, -Float::INFINITY].each do |value|
      assert_raises(JSON::GeneratorError) { SloRulesEngine::ProviderState::Fingerprint.content(value) }
      assert_raises(JSON::GeneratorError) { SloRulesEngine::ReleaseBundle::Fingerprint.content(value) }
      assert_raises(JSON::GeneratorError) { review_support.send(:fingerprint, value) }
      assert_equal "sha256:#{Digest::SHA256.hexdigest(value.to_s)}",
                   onboarding_support.send(:fingerprint, value)
    end
    invalid = "\xff".b.force_encoding(Encoding::UTF_8)
    assert_equal "sha256:#{Digest::SHA256.hexdigest(invalid)}",
                 onboarding_support.send(:fingerprint, invalid)
  end

  def test_credential_key_predicate_and_exact_finding_paths
    keys = %w[api_key API-KEY apikey app_key app-key appkey access_key access-key accesskey
              secret password token authorization credential credentials]
    fixture = keys.to_h { |key| [key, nil] }
    fixture['safe'] = [{ token: nil, 'nested' => { 'PASSWORD' => nil } }, { 'not_a_token' => nil }]
    fixture['api_key_hint'] = nil
    expected = keys.map { |key| "artifact.#{key}" } + ['artifact.safe[0].token', 'artifact.safe[0].nested.PASSWORD']
    scanners.each do |scanner|
      assert_equal expected, scanner.paths(fixture, 'artifact')
      assert_empty scanner.paths(nil, 'artifact')
      assert_empty scanner.paths({ 'Token_count' => nil, 'secretary' => nil, 'my_api_key' => nil }, 'artifact')
    end
  end

  def test_identity_assembly_and_generated_artifact_goldens
    assert_equal JSON.parse(File.read(GOLDEN_PATH)), golden_results
  end

  def test_shared_integrity_loads_without_domain_composition
    script = <<~RUBY
      require 'slo_rules_engine/artifact_integrity'
      puts JSON.generate(
        constants: SloRulesEngine.constants.map(&:to_s).sort,
        fingerprint: SloRulesEngine::ArtifactIntegrity::Fingerprint.content({}),
        paths: SloRulesEngine::ArtifactIntegrity::CredentialScanner.paths({ token: nil }, 'artifact')
      )
    RUBY
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, '-I', File.expand_path('../lib', __dir__), '-e', script
    )
    assert status.success?, stderr
    assert_empty stderr
    assert_equal({ 'constants' => ['ArtifactIntegrity'], 'fingerprint' => Digest::SHA256.hexdigest('{}'),
                   'paths' => ['artifact.token'] }, JSON.parse(stdout))
  end

  # Used once to capture the pre-extraction baseline. Expected hashes are saved,
  # never regenerated by a test or during migration.
  def golden_results
    state = SloRulesEngine::ProviderState
    desired = state::DesiredState.new(provider: 'prometheus_stack', service: 'checkout-api',
                                     source: 'reviewed_manifest', resources: { file: { objective: 99.9 } })
    observed = state::ObservedState.new(provider: 'prometheus_stack', service: 'checkout-api',
                                       source: 'managed_files', resources: {})
    plan = state::Plan.new(provider: 'prometheus_stack', service: 'checkout-api', mode: 'diff',
                           desired_state: desired, observed_state: observed, changes: [], findings: [], summary: {})
    identity = { schema_version: 'fixture/v1', target: 'checkout-api/prometheus_stack', plan: plan.to_h }
    bundle = {
      schema_version: 'slo-rules-engine/release-bundle/v1', review: { reviewer: 'maintainer@example.test' },
      targets: [{ uid: 'checkout-api/prometheus_stack' }],
      artifacts: [
        { uid: 'definition', kind: 'reviewed_definition', content_type: 'text/x-ruby', content: "# public fixture\n",
          fingerprint: 'stored-fingerprint', source: { type: 'generated', path: 'checkout.rb' } },
        { uid: 'index', kind: 'onboarding_artifact_index', fingerprint: 'excluded-from-identity' }
      ]
    }
    output = {
      'desired_state' => desired.fingerprint, 'observed_state' => observed.fingerprint, 'plan' => plan.fingerprint,
      'journal' => state::OperationJournal.journal_id_for(provider: 'prometheus_stack', service: 'checkout-api',
                                                         plan: { fingerprint: plan.fingerprint }, entries: []),
      'approved_plan' => state::ApprovedPlan::Builder.new.send(:approved_plan_id, identity),
      'bundle' => SloRulesEngine::ReleaseBundle::Fingerprint.bundle_id(bundle),
      'bundle_recomputed' => SloRulesEngine::ReleaseBundle::Fingerprint.bundle_id(bundle, recompute_artifacts: true),
      'sloth_evidence' => SloRulesEngine::Sloth::DownstreamEvidence::Support.evidence_id(identity.merge(evidence_id: 'ignored')),
      'sloth_mcp' => SloRulesEngine::Sloth::Mcp::Support.comparison_id(identity.merge(comparison_id: 'ignored'))
    }
    %w[datadog prometheus_stack sloth].each do |provider|
      manifest = reviewed_provider_manifest(provider)
      report = SloRulesEngine::ManifestReviewQueue::ReportBuilder.new.build([manifest], provider: provider)
      output["#{provider}_manifest"] = SloRulesEngine::ProviderState::Fingerprint.content(manifest)
      output["#{provider}_review"] = SloRulesEngine::ProviderState::Fingerprint.content(report)
    end
    output
  end

  private

  def review_support
    @review_support ||= SloRulesEngine::ManifestReviewQueue::ReportBuilder.new
  end

  def onboarding_support
    @onboarding_support ||= Object.new.extend(SloRulesEngine::Application::OnboardingCommandSupport)
  end

  def scanners
    [SloRulesEngine::ProviderState::CredentialScanner, SloRulesEngine::ReleaseBundle::CredentialScanner]
  end
end
