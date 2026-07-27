# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/sre'

class LiveStatusTest < Minitest::Test
  NOW = Time.utc(2026, 7, 27, 12, 0, 0)

  class FakePrometheusClient
    attr_reader :queries

    def initialize(responses)
      @responses = responses
      @queries = []
    end

    def query(expression)
      queries << expression
      response = @responses.fetch(expression)
      raise response if response.is_a?(Exception)

      response
    end
  end

  def setup
    SloRulesEngine.clear_definitions
    load File.expand_path('../examples/services/checkout.rb', __dir__)
    definition = SloRulesEngine.definitions.fetch(0)
    @manifest = SloRulesEngine.default_provider_registry.fetch('prometheus_stack')
      .generate(definition)
      .to_h
      .merge(service: definition.service)
    @responses = live_responses(@manifest)
  end

  def test_reports_healthy_reviewed_slo_with_window_and_provider_evidence
    report = read_status
    payload = report.to_h
    status = payload.fetch(:statuses).fetch(0)

    assert_equal 'slo-rules-engine/live-slo-status/v1', payload.fetch(:schema_version)
    assert_equal 'LiveSLOStatusReport', payload.fetch(:kind)
    assert_equal 'prometheus_stack', payload.fetch(:provider)
    assert_equal 'checkout-api', payload.fetch(:service)
    assert_equal({ total: 1, healthy: 1, at_risk: 0, exhausted: 0, missing_telemetry: 0, unverifiable: 0 },
                 payload.fetch(:summary))
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
    assert_equal(
      {
        target_ratio: 0.999,
        provider_target_ratio: 0.999,
        evaluation_window: '30d',
        calculation_basis: 'observations',
        success_ratio: 0.9998,
        attained: true
      },
      status.fetch(:objective)
    )
    assert_equal(
      {
        budget_ratio: 0.001,
        provider_budget_ratio: 0.001,
        remaining_ratio: 0.8,
        consumed_ratio: 0.2
      },
      status.fetch(:error_budget)
    )
    assert_equal true, status.fetch(:telemetry).fetch(:fresh)
    assert_equal 30.0, status.fetch(:telemetry).fetch(:age_seconds)
    assert_equal 'payments-platform', status.fetch(:context).fetch(:owner)
    assert_equal '/d/slo/checkout-api', status.fetch(:context).fetch(:dashboard)
    assert_equal 'https://example.com/playbooks/checkout-api', status.fetch(:context).fetch(:playbook)
    assert_equal 8, status.fetch(:provider_evidence).length
    assert_empty status.fetch(:findings)
  end

  def test_classifies_burn_breach_as_at_risk
    replace_metric('burn_rate', 15.0, range: '1h')

    status = read_status.to_h.fetch(:statuses).fetch(0)

    assert_equal 'at_risk', status.fetch(:state)
    assert_equal true, status.fetch(:burn_rate).fetch(:windows).find { |window| window[:range] == '1h' }.fetch(:breaching)
    assert_equal ['burn_rate_threshold_breached'], status.fetch(:findings).map { |finding| finding.fetch(:code) }
  end

  def test_classifies_depleted_budget_as_exhausted
    replace_metric('success_ratio', 0.998)
    replace_metric('error_budget_remaining_ratio', 0.0)

    status = read_status.to_h.fetch(:statuses).fetch(0)

    assert_equal 'exhausted', status.fetch(:state)
    assert_equal false, status.fetch(:objective).fetch(:attained)
    assert_equal ['error_budget_exhausted'], status.fetch(:findings).map { |finding| finding.fetch(:code) }
  end

  def test_classifies_absent_or_stale_samples_as_missing_telemetry
    expression = record_expression('observations')
    @responses[expression] = vector_result(nil)

    missing = read_status.to_h.fetch(:statuses).fetch(0)
    assert_equal 'missing_telemetry', missing.fetch(:state)
    assert_includes missing.fetch(:findings).map { |finding| finding.fetch(:code) }, 'missing_live_status_metric'

    @responses = live_responses(@manifest)
    @responses[freshness_expression] = vector_result((NOW - 301).to_f)
    stale = read_status.to_h.fetch(:statuses).fetch(0)

    assert_equal 'missing_telemetry', stale.fetch(:state)
    assert_equal false, stale.fetch(:telemetry).fetch(:fresh)
    assert_includes stale.fetch(:findings).map { |finding| finding.fetch(:code) }, 'stale_live_status_telemetry'
  end

  def test_classifies_ambiguous_or_failed_queries_as_unverifiable
    expression = record_expression('objective_ratio')
    @responses[expression] = {
      'resultType' => 'vector',
      'result' => [
        { 'metric' => {}, 'value' => [NOW.to_f, '0.999'] },
        { 'metric' => {}, 'value' => [NOW.to_f, '0.999'] }
      ]
    }

    ambiguous = read_status.to_h.fetch(:statuses).fetch(0)
    assert_equal 'unverifiable', ambiguous.fetch(:state)
    assert_includes ambiguous.fetch(:findings).map { |finding| finding.fetch(:code) }, 'ambiguous_live_status_metric'

    @responses = live_responses(@manifest)
    @responses[expression] = RuntimeError.new('private backend detail')
    failed = read_status.to_h.fetch(:statuses).fetch(0)

    assert_equal 'unverifiable', failed.fetch(:state)
    finding = failed.fetch(:findings).find { |entry| entry.fetch(:code) == 'provider_status_query_failed' }
    refute_nil finding
    refute_includes finding.fetch(:message), 'private backend detail'
  end

  def test_classifies_provider_objective_drift_as_unverifiable
    replace_metric('objective_ratio', 0.99)

    status = read_status.to_h.fetch(:statuses).fetch(0)

    assert_equal 'unverifiable', status.fetch(:state)
    assert_equal 0.999, status.fetch(:objective).fetch(:target_ratio)
    assert_equal 0.99, status.fetch(:objective).fetch(:provider_target_ratio)
    assert_includes status.fetch(:findings).map { |finding| finding.fetch(:code) }, 'provider_objective_mismatch'
  end

  private

  def read_status
    client = FakePrometheusClient.new(@responses)
    SloRulesEngine::LiveStatus::PrometheusReader.new(
      client: client,
      clock: -> { NOW },
      max_age_seconds: 300
    ).read(@manifest)
  end

  def live_responses(manifest)
    responses = {
      record_expression('observations') => vector_result(42.0),
      record_expression('success_ratio') => vector_result(0.9998),
      record_expression('objective_ratio') => vector_result(0.999),
      record_expression('error_budget_ratio') => vector_result(0.001),
      record_expression('error_budget_remaining_ratio') => vector_result(0.8),
      freshness_expression => vector_result((NOW - 30).to_f)
    }
    burn_rules.each do |rule|
      value = rule.fetch(:range) == '1h' ? 0.2 : 0.1
      responses[rule.fetch(:record)] = vector_result(value)
    end
    responses
  end

  def replace_metric(metric, value, range: nil)
    expression =
      if metric == 'burn_rate'
        burn_rules.find { |rule| rule.fetch(:range) == range }.fetch(:record)
      else
        record_expression(metric)
      end
    @responses[expression] = vector_result(value)
  end

  def vector_result(value)
    result =
      if value.nil?
        []
      else
        [{ 'metric' => {}, 'value' => [NOW.to_f, value.to_s] }]
      end
    { 'resultType' => 'vector', 'result' => result }
  end

  def record_expression(metric)
    recording_rules.find { |rule| rule[:metric] == metric }.fetch(:record)
  end

  def freshness_expression
    "timestamp(#{record_expression('success_ratio')})"
  end

  def recording_rules
    @manifest.fetch(:artifacts).fetch(:recording_rules)
  end

  def burn_rules
    @manifest.fetch(:artifacts).fetch(:burn_rate_rules)
  end
end
