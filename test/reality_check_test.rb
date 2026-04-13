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
end
