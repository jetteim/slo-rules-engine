# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'minitest/autorun'
require 'tmpdir'
require 'yaml'
require_relative '../lib/slo_rules_engine'
require_relative 'support/release_bundle_fixtures'

class SlothLiveStatusTest < Minitest::Test
  include ReleaseBundleFixtures

  NOW = Time.utc(2026, 8, 5, 12, 0, 0)
  GENERATED_FIXTURE = File.expand_path('fixtures/sloth/generated-rules.yaml', __dir__)

  class FakePrometheusClient
    attr_reader :queries

    def initialize(responses)
      @responses = responses
      @queries = []
    end

    def query(expression)
      queries << expression
      @responses.fetch(expression)
    end
  end

  def test_reads_every_query_only_from_fresh_reviewed_sloth_evidence
    with_sources do |sources|
      evidence = write_evidence(sources)
      responses = live_responses(evidence)
      client = FakePrometheusClient.new(responses)
      factory_calls = 0
      reader = SloRulesEngine::LiveStatus::SlothReader.new(
        client_factory: lambda {
          factory_calls += 1
          client
        },
        clock: -> { NOW },
        max_age_seconds: 300
      )

      payload = reader.read(sources.fetch(:manifest_payload), evidence_path: sources.fetch(:evidence)).to_h
      status = payload.fetch(:statuses).fetch(0)

      assert_equal 1, factory_calls
      assert_equal 'slo-rules-engine/live-slo-status/v1', payload.fetch(:schema_version)
      assert_equal 'sloth', payload.fetch(:provider)
      assert_equal 'checkout-api', payload.fetch(:service)
      assert_equal 'healthy', status.fetch(:state)
      assert_equal(
        {
          service: 'checkout-api',
          sli: 'http-requests',
          sli_instance: 'public-api',
          slo: 'successful-requests'
        },
        status.fetch(:identity)
      )
      assert_equal 'observations', status.dig(:objective, :calculation_basis)
      assert_equal 0.9998, status.dig(:objective, :success_ratio)
      assert_equal 0.8, status.dig(:error_budget, :remaining_ratio)
      assert_equal 42.0, status.dig(:telemetry, :observations)
      assert_equal true, status.dig(:telemetry, :fresh)
      assert_equal 30.0, status.dig(:telemetry, :age_seconds)
      assert_equal 'payments-platform', status.dig(:context, :owner)
      assert_equal '/d/slo/checkout-api', status.dig(:context, :dashboard)
      assert_equal 'https://example.com/playbooks/checkout-api', status.dig(:context, :playbook)
      assert_equal evidence.fetch(:evidence_id), status.dig(:provider_resources, :evidence_id)
      assert_equal evidence.dig(:slos, 0, :identity, :sloth_id), status.dig(:provider_resources, :sloth_id)
      assert_equal 8, status.fetch(:provider_evidence).length
      assert_equal responses.keys.sort, client.queries.sort
      assert_empty status.fetch(:findings)
    end
  end

  def test_rejects_stale_evidence_before_constructing_the_backend_client
    with_sources do |sources|
      write_evidence(sources)
      generated = YAML.safe_load(File.read(sources.fetch(:generated)), aliases: false)
      generated.fetch('groups').fetch(0).fetch('rules').fetch(0)['expr'] = 'vector(0)'
      File.write(sources.fetch(:generated), YAML.dump(generated))
      factory_calls = 0
      reader = SloRulesEngine::LiveStatus::SlothReader.new(
        client_factory: lambda {
          factory_calls += 1
          FakePrometheusClient.new({})
        }
      )

      error = assert_raises(SloRulesEngine::Sloth::DownstreamEvidence::ContractError) do
        reader.read(sources.fetch(:manifest_payload), evidence_path: sources.fetch(:evidence))
      end

      assert_equal 0, factory_calls
      assert_includes error.findings.map { |finding| finding.fetch(:code) }, 'stale_generated_rules'
    end
  end

  def test_classifies_sloth_burn_budget_and_query_failures_with_the_neutral_states
    with_sources do |sources|
      evidence = write_evidence(sources)
      responses = live_responses(evidence)
      bindings = evidence.dig(:slos, 0, :status_bindings)

      responses[bindings.dig(:burn_rate, 0, :query)] = vector_result(2.0)
      at_risk = read_status(sources, evidence, responses)
      assert_equal 'at_risk', at_risk.fetch(:state)
      assert_includes at_risk.fetch(:findings).map { |finding| finding.fetch(:code) },
                      'burn_rate_threshold_breached'

      responses = live_responses(evidence)
      responses[bindings.dig(:success_ratio, :query)] = vector_result(0.998)
      responses[bindings.dig(:error_budget_remaining_ratio, :query)] = vector_result(0.0)
      exhausted = read_status(sources, evidence, responses)
      assert_equal 'exhausted', exhausted.fetch(:state)
      assert_includes exhausted.fetch(:findings).map { |finding| finding.fetch(:code) },
                      'error_budget_exhausted'

      responses = live_responses(evidence)
      responses[bindings.dig(:observations, :query)] = empty_vector_result
      missing = read_status(sources, evidence, responses)
      assert_equal 'missing_telemetry', missing.fetch(:state)
      assert_includes missing.fetch(:findings).map { |finding| finding.fetch(:code) },
                      'missing_live_status_metric'

      responses = live_responses(evidence)
      responses[bindings.dig(:objective_ratio, :query)] = {
        'resultType' => 'vector',
        'result' => [
          { 'metric' => {}, 'value' => [NOW.to_f, '0.999'] },
          { 'metric' => {}, 'value' => [NOW.to_f, '0.999'] }
        ]
      }
      unverifiable = read_status(sources, evidence, responses)
      assert_equal 'unverifiable', unverifiable.fetch(:state)
      assert_includes unverifiable.fetch(:findings).map { |finding| finding.fetch(:code) },
                      'ambiguous_live_status_metric'
    end
  end

  def test_rejects_evidence_for_a_different_manifest_before_backend_access
    with_sources do |sources|
      write_evidence(sources)
      different_manifest = Marshal.load(Marshal.dump(sources.fetch(:manifest_payload)))
      different_manifest.fetch(:review_provenance).fetch(:notes) << 'A later review note.'
      factory_calls = 0
      reader = SloRulesEngine::LiveStatus::SlothReader.new(
        client_factory: lambda {
          factory_calls += 1
          FakePrometheusClient.new({})
        }
      )

      error = assert_raises(SloRulesEngine::Sloth::DownstreamEvidence::ContractError) do
        reader.read(different_manifest, evidence_path: sources.fetch(:evidence))
      end

      assert_equal 0, factory_calls
      assert_includes error.findings.map { |finding| finding.fetch(:code) },
                      'sloth_manifest_evidence_mismatch'
    end
  end

  def test_rejects_rehashed_observation_query_drift_before_backend_access
    with_sources do |sources|
      evidence = write_evidence(sources)
      evidence.fetch(:slos).fetch(0).fetch(:status_bindings).fetch(:observations)[:query] = 'vector(1)'
      evidence[:evidence_id] = SloRulesEngine::Sloth::DownstreamEvidence::Support.evidence_id(evidence)
      File.write(sources.fetch(:evidence), JSON.pretty_generate(evidence))
      factory_calls = 0
      reader = SloRulesEngine::LiveStatus::SlothReader.new(
        client_factory: lambda {
          factory_calls += 1
          FakePrometheusClient.new({})
        }
      )

      error = assert_raises(SloRulesEngine::Sloth::DownstreamEvidence::ContractError) do
        reader.read(sources.fetch(:manifest_payload), evidence_path: sources.fetch(:evidence))
      end

      assert_equal 0, factory_calls
      assert_includes error.findings.map { |finding| finding.fetch(:code) },
                      'sloth_evidence_source_derivation_mismatch'
    end
  end

  private

  def with_sources
    Dir.mktmpdir do |dir|
      manifest = reviewed_provider_manifest('sloth')
      manifest_path = File.join(dir, 'manifest.json')
      input_path = File.join(dir, 'sloth.yaml')
      generated_path = File.join(dir, 'generated-rules.yaml')
      evidence_path = File.join(dir, 'sloth-evidence.json')
      File.write(manifest_path, JSON.pretty_generate(manifest))
      File.write(input_path, YAML.dump(JSON.parse(JSON.generate(manifest.dig(:artifacts, :sloth_specs, 0)))))
      FileUtils.cp(GENERATED_FIXTURE, generated_path)
      yield(
        manifest: manifest_path,
        manifest_payload: manifest,
        input: input_path,
        generated: generated_path,
        evidence: evidence_path
      )
    end
  end

  def write_evidence(sources)
    evidence = SloRulesEngine::Sloth::DownstreamEvidence::Builder.new.build(
      manifest_path: sources.fetch(:manifest),
      input_paths: [sources.fetch(:input)],
      generated_rules_path: sources.fetch(:generated),
      reviewer: 'platform-reviewer@example.test',
      reviewed_at: '2026-08-05T11:00:00Z'
    )
    File.write(sources.fetch(:evidence), JSON.pretty_generate(evidence))
    evidence
  end

  def live_responses(evidence)
    bindings = evidence.dig(:slos, 0, :status_bindings)
    {
      bindings.dig(:observations, :query) => vector_result(42.0),
      bindings.dig(:success_ratio, :query) => vector_result(0.9998),
      bindings.dig(:objective_ratio, :query) => vector_result(0.999),
      bindings.dig(:error_budget_ratio, :query) => vector_result(0.001),
      bindings.dig(:error_budget_remaining_ratio, :query) => vector_result(0.8),
      bindings.dig(:burn_rate, 0, :query) => vector_result(0.2),
      bindings.dig(:burn_rate, 1, :query) => vector_result(0.2),
      bindings.dig(:freshness, :query) => vector_result((NOW - 30).to_f)
    }
  end

  def read_status(sources, _evidence, responses)
    SloRulesEngine::LiveStatus::SlothReader.new(
      client_factory: -> { FakePrometheusClient.new(responses) },
      clock: -> { NOW },
      max_age_seconds: 300
    ).read(sources.fetch(:manifest_payload), evidence_path: sources.fetch(:evidence))
      .to_h.fetch(:statuses).fetch(0)
  end

  def vector_result(value)
    {
      'resultType' => 'vector',
      'result' => [{ 'metric' => {}, 'value' => [NOW.to_f, value.to_s] }]
    }
  end

  def empty_vector_result
    { 'resultType' => 'vector', 'result' => [] }
  end
end
