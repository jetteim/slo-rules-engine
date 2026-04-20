# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/sre'

class RealityCheckTest < Minitest::Test
  def test_recommends_observations_for_high_volume
    result = SloRulesEngine::RealityCheck::CalculationBasisAdvisor.new.recommend(
      observations_per_second: 10,
      failed_observations_to_alert: 100
    )

    assert_equal 'observations', result.basis
    assert_equal 'high', result.confidence
  end

  def test_recommends_time_slice_when_too_few_failures_alert
    result = SloRulesEngine::RealityCheck::CalculationBasisAdvisor.new.recommend(
      observations_per_second: 0.01,
      failed_observations_to_alert: 1
    )

    assert_equal 'time_slice', result.basis
    assert_equal 'high', result.confidence
  end

  def test_low_volume_fixture_recommends_time_slice
    recommendation = SloRulesEngine::RealityCheck::CalculationBasisAdvisor.new.recommend(
      observations_per_second: 0.1,
      failed_observations_to_alert: 1
    )

    assert_equal 'time_slice', recommendation.basis
  end

  def test_checks_provider_bindings_against_measured_telemetry
    SloRulesEngine.clear_definitions
    load File.expand_path('../examples/services/checkout.rb', __dir__)
    definition = SloRulesEngine.definitions.fetch(0)

    report = SloRulesEngine::RealityCheck::TelemetryBindingChecker.new(provider: 'datadog').check(
      definition,
      [{ metric: 'http.server.request.duration' }]
    )

    assert report.valid?, report.to_h.inspect
  end

  def test_reports_missing_provider_telemetry
    SloRulesEngine.clear_definitions
    load File.expand_path('../examples/services/checkout.rb', __dir__)
    definition = SloRulesEngine.definitions.fetch(0)

    report = SloRulesEngine::RealityCheck::TelemetryBindingChecker.new(provider: 'datadog').check(
      definition,
      [{ metric: 'other.metric' }]
    )

    refute report.valid?
    assert_equal 'missing_provider_metric', report.findings.fetch(0)[:code]
    assert_equal 'http.server.request.duration', report.findings.fetch(0)[:metric]
  end

  def test_reports_missing_backend_series_from_lookup_findings
    definition = load_checkout
    lookup_result = SloRulesEngine::TelemetryLookup::Result.new(
      provider: 'datadog',
      findings: [
        SloRulesEngine::TelemetryLookup::Finding.new(
          code: 'missing_backend_series',
          provider: 'datadog',
          metric: 'http.server.request.duration',
          message: 'no series'
        )
      ]
    )

    report = SloRulesEngine::RealityCheck::TelemetryBindingChecker.new(provider: 'datadog').check(
      definition,
      [{ metric: 'http.server.request.duration' }],
      lookup_results: [lookup_result]
    )

    refute report.valid?
    finding = report.findings.find { |candidate| candidate[:code] == 'missing_backend_series' }
    assert_equal 'http.server.request.duration', finding[:metric]
    assert_equal 'datadog', finding[:provider]
  end

  def test_reports_missing_histogram_bucket_for_histogram_metric_without_bucket_signal
    definition = load_checkout
    binding = definition.slis.fetch(0).metric.binding_for('prometheus_stack')

    report = SloRulesEngine::RealityCheck::TelemetryBindingChecker.new(provider: 'prometheus_stack').check(
      definition,
      [{ metric: binding.metric }]
    )

    refute report.valid?
    finding = report.findings.find { |candidate| candidate[:code] == 'missing_histogram_bucket' }
    assert_equal 'http_server_request_duration_seconds_bucket', finding[:metric]
  end

  def test_reports_calculation_basis_risk_from_lookup_volume
    definition = load_checkout
    low_volume = {
      metric: 'http.server.request.duration',
      observations_per_second: 0.01,
      failed_observations_to_alert: 1
    }
    high_volume_time_slice = {
      metric: 'http.server.request.duration',
      observations_per_second: 25,
      failed_observations_to_alert: 120,
      calculation_basis: 'time_slice'
    }

    low_report = SloRulesEngine::RealityCheck::TelemetryBindingChecker.new(provider: 'datadog').check(
      definition,
      [low_volume]
    )
    high_report = SloRulesEngine::RealityCheck::TelemetryBindingChecker.new(provider: 'datadog').check(
      definition,
      [high_volume_time_slice]
    )

    assert low_report.findings.any? { |finding| finding[:code] == 'calculation_basis_low_volume' }
    assert high_report.findings.any? { |finding| finding[:code] == 'calculation_basis_high_volume' }
  end

  private

  def load_checkout
    SloRulesEngine.clear_definitions
    load File.expand_path('../examples/services/checkout.rb', __dir__)
    SloRulesEngine.definitions.fetch(0)
  end
end
