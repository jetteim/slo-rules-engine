# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/sre'
require 'tempfile'

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

  def test_reports_calculation_basis_risk_for_each_slo_instance
    definition = load_multi_instance_calculation_basis_definition

    low_report = SloRulesEngine::RealityCheck::TelemetryBindingChecker.new(provider: 'datadog').check(
      definition,
      [{
        metric: 'http.server.request.duration',
        observations_per_second: 0.01,
        failed_observations_to_alert: 1
      }]
    )
    high_report = SloRulesEngine::RealityCheck::TelemetryBindingChecker.new(provider: 'datadog').check(
      definition,
      [{
        metric: 'http.server.request.duration',
        observations_per_second: 25,
        failed_observations_to_alert: 120
      }]
    )

    low_volume_finding = low_report.findings.find { |finding| finding[:code] == 'calculation_basis_low_volume' }
    high_volume_finding = high_report.findings.find { |finding| finding[:code] == 'calculation_basis_high_volume' }

    assert_equal 'public-api', low_volume_finding[:sli_instance]
    assert_equal 'successful-requests', low_volume_finding[:slo]
    assert_equal 'partner-api', high_volume_finding[:sli_instance]
    assert_equal 'successful-requests', high_volume_finding[:slo]
  end

  private

  def load_checkout
    SloRulesEngine.clear_definitions
    load File.expand_path('../examples/services/checkout.rb', __dir__)
    SloRulesEngine.definitions.fetch(0)
  end

  def load_multi_instance_calculation_basis_definition
    Tempfile.create(['multi-instance-calculation-basis', '.rb']) do |file|
      file.write(<<~RUBY)
        require_relative '#{File.expand_path('../lib/sre', __dir__)}'

        SRE.define do
          service 'checkout-api'
          owner 'payments-platform'

          notification_route(
            key: 'checkout-api',
            source: 'datadog',
            provider: 'msteams',
            target: 'payments-checkout'
          )

          sli do
            uid 'http-requests'
            title 'HTTP requests'

            metric 'http.server.request.duration' do
              provider_binding :datadog do
                data_source 'datadog'
                metric 'http.server.request.duration'
                type 'histogram'
                query 'p95:http.server.request.duration{service:checkout-api}'
                selector service: 'checkout-api'
              end
            end

            instance do
              uid 'public-api'
              selector route: '/checkout'

              slo do
                uid 'successful-requests'
                objective 0.999
                calculation_basis 'observations'
                success_selector status: 'success'
              end
            end

            instance do
              uid 'partner-api'
              selector route: '/partner-checkout'

              slo do
                uid 'successful-requests'
                objective 0.999
                calculation_basis 'time_slice'
                success_selector status: 'success'
              end
            end
          end
        end
      RUBY
      file.flush

      SloRulesEngine.clear_definitions
      load file.path
      return SloRulesEngine.definitions.fetch(0)
    end
  end
end
