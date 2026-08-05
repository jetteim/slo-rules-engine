# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'minitest/autorun'
require 'tmpdir'
require 'yaml'
require_relative '../lib/slo_rules_engine'
require_relative 'support/release_bundle_fixtures'

class SlothDownstreamEvidenceTest < Minitest::Test
  include ReleaseBundleFixtures

  FIXTURE = File.expand_path('fixtures/sloth/generated-rules.yaml', __dir__)

  def test_builds_content_addressed_reviewed_evidence_for_every_sloth_slo
    with_sources do |sources|
      evidence = build_evidence(sources)

      assert_equal 'slo-rules-engine/sloth-downstream-evidence/v1', evidence.fetch(:schema_version)
      assert_equal 'SlothDownstreamEvidence', evidence.fetch(:kind)
      assert_match(/\Asloth-evidence-[0-9a-f]{64}\z/, evidence.fetch(:evidence_id))
      assert_equal 'sloth', evidence.fetch(:provider)
      assert_equal 'checkout-api', evidence.fetch(:service)
      assert_equal 'platform-reviewer@example.test', evidence.dig(:review, :reviewer)
      assert_equal '2026-08-04T12:00:00Z', evidence.dig(:review, :reviewed_at)
      assert_equal 1, evidence.dig(:summary, :expected_slos)
      assert_equal 1, evidence.dig(:summary, :mapped_slos)
      assert evidence.dig(:summary, :complete)
      assert_empty evidence.fetch(:findings)

      source = evidence.fetch(:source)
      assert_equal sources.fetch(:manifest), source.dig(:manifest, :path)
      assert_match(/\A[0-9a-f]{64}\z/, source.dig(:manifest, :fingerprint))
      assert_equal [sources.fetch(:input)], source.fetch(:native_inputs).map { |entry| entry.fetch(:path) }
      assert_equal sources.fetch(:generated), source.dig(:generated_rules, :path)

      slo = evidence.fetch(:slos).fetch(0)
      assert_equal 'checkout-api/http-requests-public-api-successful-requests', slo.fetch(:uid)
      assert_equal 'checkout-api-http-requests-public-api-successful-requests', slo.dig(:identity, :sloth_id)
      assert_equal 0.999, slo.dig(:reviewed_intent, :objective_ratio)
      assert_equal '30d', slo.dig(:reviewed_intent, :evaluation_window)
      assert_equal %i[
        base_error_ratio
        evaluation_error_ratio
        objective_ratio
        error_budget_ratio
        time_period_days
        current_burn_rate_ratio
        period_burn_rate_ratio
        error_budget_remaining_ratio
        metadata
      ], slo.fetch(:recording_rules).keys
      assert_equal 'slo:sli_error:ratio_rate30d',
                   slo.dig(:recording_rules, :evaluation_error_ratio, :record)
      assert_includes slo.dig(:recording_rules, :objective_ratio, :selector),
                      'sloth_id="checkout-api-http-requests-public-api-successful-requests"'

      bindings = slo.fetch(:status_bindings)
      assert_equal %i[
        observations
        success_ratio
        objective_ratio
        error_budget_ratio
        error_budget_remaining_ratio
        burn_rate
        freshness
      ], bindings.keys
      assert_equal 'reviewed_native_input_query', bindings.dig(:observations, :kind)
      assert_includes bindings.dig(:observations, :query), 'http_server_request_duration_seconds_count'
      assert_equal 'derived_from_recording_rule', bindings.dig(:success_ratio, :kind)
      assert_includes bindings.dig(:success_ratio, :query), '1 - ('
      assert_equal 2, bindings.fetch(:burn_rate).length
      assert_equal [1.0, 1.0], bindings.fetch(:burn_rate).map { |binding| binding.fetch(:threshold) }
      assert_includes bindings.dig(:freshness, :query), 'timestamp('

      serialized = JSON.generate(evidence)
      refute_match(/api[_-]?key|app[_-]?key|authorization/i, serialized)
    end
  end

  def test_rejects_missing_ambiguous_and_unrelated_generated_recording_rules
    with_sources do |sources|
      generated = YAML.safe_load(File.read(sources.fetch(:generated)), aliases: true)
      meta_rules = generated.fetch('groups').fetch(1).fetch('rules')

      missing = Marshal.load(Marshal.dump(generated))
      missing.fetch('groups').fetch(1).fetch('rules').reject! do |rule|
        rule['record'] == 'slo:period_error_budget_remaining:ratio'
      end
      write_yaml(sources.fetch(:generated), missing)
      error = assert_raises(SloRulesEngine::Sloth::DownstreamEvidence::ContractError) do
        build_evidence(sources)
      end
      assert_includes finding_codes(error), 'missing_generated_recording_rule'

      ambiguous = Marshal.load(Marshal.dump(generated))
      ambiguous.fetch('groups').fetch(1).fetch('rules') << Marshal.load(Marshal.dump(meta_rules.fetch(0)))
      write_yaml(sources.fetch(:generated), ambiguous)
      error = assert_raises(SloRulesEngine::Sloth::DownstreamEvidence::ContractError) do
        build_evidence(sources)
      end
      assert_includes finding_codes(error), 'ambiguous_generated_recording_rule'

      unrelated = Marshal.load(Marshal.dump(generated))
      unrelated_rule = Marshal.load(Marshal.dump(meta_rules.fetch(0)))
      unrelated_rule.fetch('labels')['sloth_slo'] = 'unreviewed-slo'
      unrelated.fetch('groups').fetch(1).fetch('rules') << unrelated_rule
      write_yaml(sources.fetch(:generated), unrelated)
      error = assert_raises(SloRulesEngine::Sloth::DownstreamEvidence::ContractError) do
        build_evidence(sources)
      end
      assert_includes finding_codes(error), 'unrelated_generated_recording_rule'
    end
  end

  def test_rejects_unreviewed_manifest_input_drift_and_credential_like_content
    with_sources do |sources|
      manifest = JSON.parse(File.read(sources.fetch(:manifest)))
      manifest.delete('review_provenance')
      File.write(sources.fetch(:manifest), JSON.pretty_generate(manifest))
      error = assert_raises(SloRulesEngine::Sloth::DownstreamEvidence::ContractError) do
        build_evidence(sources)
      end
      assert_includes finding_codes(error), 'missing_review_provenance'
    end

    with_sources do |sources|
      input = YAML.safe_load(File.read(sources.fetch(:input)), aliases: false)
      input.fetch('labels')['owner'] = 'another-team'
      write_yaml(sources.fetch(:input), input)
      error = assert_raises(SloRulesEngine::Sloth::DownstreamEvidence::ContractError) do
        build_evidence(sources)
      end
      assert_includes finding_codes(error), 'native_input_manifest_mismatch'
    end

    with_sources do |sources|
      generated = YAML.safe_load(File.read(sources.fetch(:generated)), aliases: true)
      generated['credentials'] = { 'password' => 'not-a-real-secret' }
      write_yaml(sources.fetch(:generated), generated)
      error = assert_raises(SloRulesEngine::Sloth::DownstreamEvidence::ContractError) do
        build_evidence(sources)
      end
      assert_includes finding_codes(error), 'credential_like_key'
    end
  end

  def test_status_is_fresh_then_fails_closed_when_a_source_changes
    with_sources do |sources|
      evidence = build_evidence(sources)
      evidence_path = File.join(sources.fetch(:dir), 'sloth-evidence.json')
      File.write(evidence_path, JSON.pretty_generate(evidence))

      fresh = SloRulesEngine::Sloth::DownstreamEvidence::StatusEvaluator.new.evaluate(evidence_path)
      assert_equal 'slo-rules-engine/sloth-downstream-evidence-status/v1', fresh.fetch(:schema_version)
      assert_equal 'fresh', fresh.fetch(:status)
      assert fresh.fetch(:fresh)
      assert_empty fresh.fetch(:findings)
      assert fresh.fetch(:source_checks).all? { |check| check.fetch(:fresh) }

      generated = YAML.safe_load(File.read(sources.fetch(:generated)), aliases: true)
      generated.fetch('groups').fetch(0).fetch('rules').fetch(0)['expr'] = 'vector(0)'
      write_yaml(sources.fetch(:generated), generated)

      stale = SloRulesEngine::Sloth::DownstreamEvidence::StatusEvaluator.new.evaluate(evidence_path)
      assert_equal 'stale', stale.fetch(:status)
      refute stale.fetch(:fresh)
      assert_includes stale.fetch(:findings).map { |finding| finding.fetch(:code) },
                      'stale_generated_rules'
    end
  end

  def test_status_rejects_tampered_evidence_identity_without_trusting_source_paths
    with_sources do |sources|
      evidence = build_evidence(sources)
      evidence[:service] = 'tampered-service'
      evidence_path = File.join(sources.fetch(:dir), 'sloth-evidence.json')
      File.write(evidence_path, JSON.pretty_generate(evidence))

      error = assert_raises(SloRulesEngine::Sloth::DownstreamEvidence::ContractError) do
        SloRulesEngine::Sloth::DownstreamEvidence::StatusEvaluator.new.evaluate(evidence_path)
      end
      assert_includes finding_codes(error), 'sloth_evidence_identity_mismatch'
    end
  end

  def test_status_rejects_rehashed_but_incomplete_evidence_schema_before_source_reads
    with_sources do |sources|
      evidence = build_evidence(sources)
      evidence.fetch(:slos).fetch(0).fetch(:status_bindings).delete(:observations)
      evidence.fetch(:source).fetch(:manifest)[:path] = File.join(sources.fetch(:dir), 'must-not-be-read.json')
      evidence[:evidence_id] = SloRulesEngine::Sloth::DownstreamEvidence::Support.evidence_id(evidence)
      evidence_path = File.join(sources.fetch(:dir), 'sloth-evidence.json')
      File.write(evidence_path, JSON.pretty_generate(evidence))

      error = assert_raises(SloRulesEngine::Sloth::DownstreamEvidence::ContractError) do
        SloRulesEngine::Sloth::DownstreamEvidence::StatusEvaluator.new.evaluate(evidence_path)
      end
      assert_includes finding_codes(error), 'invalid_sloth_evidence_schema'
      refute_includes finding_codes(error), 'unreadable_sloth_manifest'
    end
  end

  def test_status_rejects_rehashed_query_drift_before_source_reads
    with_sources do |sources|
      evidence = build_evidence(sources)
      evidence.fetch(:slos).fetch(0).fetch(:status_bindings).fetch(:success_ratio)[:query] = 'vector(1)'
      evidence.fetch(:source).fetch(:manifest)[:path] = File.join(sources.fetch(:dir), 'must-not-be-read.json')
      evidence[:evidence_id] = SloRulesEngine::Sloth::DownstreamEvidence::Support.evidence_id(evidence)
      evidence_path = File.join(sources.fetch(:dir), 'sloth-evidence.json')
      File.write(evidence_path, JSON.pretty_generate(evidence))

      error = assert_raises(SloRulesEngine::Sloth::DownstreamEvidence::ContractError) do
        SloRulesEngine::Sloth::DownstreamEvidence::StatusEvaluator.new.evaluate(evidence_path)
      end
      assert_includes finding_codes(error), 'invalid_sloth_evidence_schema'
      refute_includes finding_codes(error), 'unreadable_sloth_manifest'
    end
  end

  private

  def with_sources
    Dir.mktmpdir do |dir|
      manifest = reviewed_provider_manifest('sloth')
      manifest_path = File.join(dir, 'manifest.json')
      input_path = File.join(dir, 'sloth.yaml')
      generated_path = File.join(dir, 'generated-rules.yaml')
      File.write(manifest_path, JSON.pretty_generate(manifest))
      spec = manifest.fetch(:artifacts).fetch(:sloth_specs).fetch(0)
      File.write(input_path, YAML.dump(JSON.parse(JSON.generate(spec))))
      FileUtils.cp(FIXTURE, generated_path)
      yield(dir: dir, manifest: manifest_path, input: input_path, generated: generated_path)
    end
  end

  def build_evidence(sources)
    SloRulesEngine::Sloth::DownstreamEvidence::Builder.new.build(
      manifest_path: sources.fetch(:manifest),
      input_paths: [sources.fetch(:input)],
      generated_rules_path: sources.fetch(:generated),
      reviewer: 'platform-reviewer@example.test',
      reviewed_at: '2026-08-04T12:00:00Z'
    )
  end

  def finding_codes(error)
    error.findings.map { |finding| finding.fetch(:code) }
  end

  def write_yaml(path, payload)
    File.write(path, YAML.dump(payload))
  end
end
