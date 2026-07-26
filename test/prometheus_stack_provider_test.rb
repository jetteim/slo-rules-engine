# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/sre'

class PrometheusStackProviderTest < Minitest::Test
  PROMETHEUS_METRIC_NAME = /\A[a-zA-Z_:][a-zA-Z0-9_:]*\z/

  def setup
    SloRulesEngine.clear_definitions
    load File.expand_path('../examples/services/checkout.rb', __dir__)
    @definition = SloRulesEngine.definitions.fetch(0)
    @provider = SloRulesEngine.default_provider_registry.fetch('prometheus_stack')
  end

  def test_generates_one_base_recording_rule_per_sli_instance
    first_sli = @definition.slis.fetch(0)
    second_slo = deep_copy(first_sli.instances.fetch(0).slos.fetch(0))
    second_slo.uid = 'strict-success'
    first_sli.instances.fetch(0).slos << second_slo

    second_sli = deep_copy(first_sli)
    second_sli.uid = 'checkout-traffic'
    second_sli.title = 'Checkout traffic'
    second_sli.instances.fetch(0).uid = 'aggregate'
    second_sli.instances.fetch(0).slos = [second_sli.instances.fetch(0).slos.fetch(0)]
    second_sli.instances.fetch(0).slos.fetch(0).uid = 'traffic-quality'
    @definition.slis << second_sli

    artifacts = @provider.generate(@definition).to_h.fetch(:artifacts)
    sli_rules = artifacts.fetch(:recording_rules).select { |rule| rule[:kind] == 'sli' }

    assert_equal 2, sli_rules.length
    assert_equal(
      %w[
        sli:checkout_api:checkout_traffic:aggregate:observations
        sli:checkout_api:http_requests:public_api:observations
      ],
      sli_rules.map { |rule| rule.fetch(:record) }.sort
    )
    assert_equal 12, artifacts.fetch(:recording_rules).count { |rule| rule[:kind] == 'slo' }
    assert_equal 6, artifacts.fetch(:burn_rate_rules).length
  end

  def test_generates_queryable_semantic_recording_rules_for_each_slo
    artifacts = @provider.generate(@definition).to_h.fetch(:artifacts)
    recording_rules = artifacts.fetch(:recording_rules)

    sli_rule = recording_rules.find { |rule| rule[:kind] == 'sli' }
    assert_equal 'sli:checkout_api:http_requests:public_api:observations', sli_rule.fetch(:record)
    assert_equal 'sum(rate(http_server_request_duration_seconds_count{service="checkout-api",route="/checkout"}[5m]))',
                 sli_rule.fetch(:expr)
    assert_equal 'public-api', sli_rule.fetch(:labels).fetch(:sli_instance)
    refute_includes sli_rule.fetch(:labels), :slo

    slo_rules = recording_rules.select { |rule| rule[:kind] == 'slo' }
    assert_equal 4, slo_rules.length
    rules_by_metric = slo_rules.to_h { |rule| [rule.fetch(:metric), rule] }
    assert_equal %w[error_budget_ratio error_ratio objective_ratio success_ratio], rules_by_metric.keys.sort
    assert_equal 'vector(0.999)', rules_by_metric.fetch('objective_ratio').fetch(:expr)
    assert_equal 'vector(0.001)', rules_by_metric.fetch('error_budget_ratio').fetch(:expr)
    assert_equal(
      '1 - slo:checkout_api:http_requests:public_api:successful_requests:success_ratio',
      rules_by_metric.fetch('error_ratio').fetch(:expr)
    )
  end

  def test_all_record_names_are_valid_prometheus_metric_names
    artifacts = @provider.generate(@definition).to_h.fetch(:artifacts)
    rules = artifacts.fetch(:recording_rules) + artifacts.fetch(:burn_rate_rules)

    rules.each do |rule|
      assert_match PROMETHEUS_METRIC_NAME, rule.fetch(:record)
    end
  end

  def test_generates_time_slice_success_ratio_for_numeric_threshold_slo
    sli = @definition.slis.fetch(0)
    binding = sli.metric.binding_for('prometheus_stack')
    binding.query = 'sum(rate(http_server_request_duration_seconds_count{service="checkout-api"}[5m]))'
    slo = sli.instances.fetch(0).slos.fetch(0)
    slo.success_selector = nil
    slo.success_threshold = { operator: '<=', value: '0.5' }
    slo.calculation_basis = 'time_slice'

    result = @provider.validate(@definition)
    rule = @provider.generate(@definition).to_h.fetch(:artifacts).fetch(:recording_rules).find do |entry|
      entry[:metric] == 'success_ratio'
    end

    assert result.valid?, result.errors.map(&:to_h).inspect
    assert_equal(
      'avg_over_time(((sum(rate(http_server_request_duration_seconds_count{service="checkout-api"}[5m]))) <= bool 0.5)[5m:])',
      rule.fetch(:expr)
    )
  end

  def test_rejects_non_numeric_or_observation_based_threshold_slo
    slo = @definition.slis.fetch(0).instances.fetch(0).slos.fetch(0)
    slo.success_selector = nil
    slo.success_threshold = { operator: '<=', value: 'review-me' }
    slo.calculation_basis = 'observations'

    result = @provider.validate(@definition)

    refute result.valid?
    assert result.errors.any? { |error| error.path.end_with?('.success_threshold.value') && error.message.include?('numeric') }
    assert result.errors.any? { |error| error.path.end_with?('.calculation_basis') && error.message.include?('time_slice') }
  end

  private

  def deep_copy(value)
    Marshal.load(Marshal.dump(value))
  end
end
