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
    assert_equal 15, artifacts.fetch(:recording_rules).count { |rule| rule[:kind] == 'slo' }
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
    assert_equal 5, slo_rules.length
    rules_by_metric = slo_rules.to_h { |rule| [rule.fetch(:metric), rule] }
    assert_equal(
      %w[error_budget_ratio error_budget_remaining_ratio error_ratio objective_ratio success_ratio],
      rules_by_metric.keys.sort
    )
    assert_equal(
      'sum(rate(http_server_request_duration_seconds_count{service="checkout-api",route="/checkout",status="success"}[30d])) / ' \
      'sum(rate(http_server_request_duration_seconds_count{service="checkout-api",route="/checkout"}[30d]))',
      rules_by_metric.fetch('success_ratio').fetch(:expr)
    )
    assert_equal 'vector(0.999)', rules_by_metric.fetch('objective_ratio').fetch(:expr)
    assert_equal 'vector(0.001)', rules_by_metric.fetch('error_budget_ratio').fetch(:expr)
    assert_equal(
      '1 - slo:checkout_api:http_requests:public_api:successful_requests:success_ratio',
      rules_by_metric.fetch('error_ratio').fetch(:expr)
    )
    assert_equal(
      'clamp(1 - (slo:checkout_api:http_requests:public_api:successful_requests:error_ratio / ' \
      'slo:checkout_api:http_requests:public_api:successful_requests:error_budget_ratio), 0, 1)',
      rules_by_metric.fetch('error_budget_remaining_ratio').fetch(:expr)
    )
    slo_rules.each do |rule|
      assert_equal '30d', rule.fetch(:labels).fetch(:evaluation_window)
    end

    burn_rules = artifacts.fetch(:burn_rate_rules)
    assert_equal(
      '(1 - (sum(rate(http_server_request_duration_seconds_count{service="checkout-api",route="/checkout",status="success"}[1h])) / ' \
      'sum(rate(http_server_request_duration_seconds_count{service="checkout-api",route="/checkout"}[1h])))) / 0.001',
      burn_rules.find { |rule| rule.fetch(:range) == '1h' }.fetch(:expr)
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
      'avg_over_time(((sum(rate(http_server_request_duration_seconds_count{service="checkout-api"}[5m]))) <= bool 0.5)[30d:])',
      rule.fetch(:expr)
    )

    burn_rule = @provider.generate(@definition).to_h.fetch(:artifacts).fetch(:burn_rate_rules).find do |entry|
      entry[:range] == '1h'
    end
    assert_equal(
      '(1 - (avg_over_time(((sum(rate(http_server_request_duration_seconds_count{service="checkout-api"}[5m]))) <= bool 0.5)[1h:]))) / 0.001',
      burn_rule.fetch(:expr)
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

  def test_renders_native_prometheus_rule_resource
    artifacts = @provider.generate(@definition).to_h.fetch(:artifacts)
    resource = artifacts.fetch(:prometheus_rule_resources).fetch(0)

    assert_equal 'monitoring.coreos.com/v1', resource.fetch(:apiVersion)
    assert_equal 'PrometheusRule', resource.fetch(:kind)
    assert_equal 'checkout-api-slo-rules', resource.fetch(:metadata).fetch(:name)
    assert_equal 'slo-rules-engine', resource.fetch(:metadata).fetch(:labels).fetch('app.kubernetes.io/managed-by')
    assert_equal 'service/checkout-api',
                 resource.fetch(:metadata).fetch(:annotations).fetch('slo-rules-engine.io/source-ref')

    groups = resource.fetch(:spec).fetch(:groups)
    assert_equal(
      %w[
        checkout-api.sli-recording
        checkout-api.slo-recording
        checkout-api.slo-burn-rate
        checkout-api.slo-alerts
      ],
      groups.map { |group| group.fetch(:name) }
    )
    assert_equal [1, 5, 2, 2], groups.map { |group| group.fetch(:rules).length }

    recording_rule = groups.fetch(0).fetch(:rules).fetch(0)
    assert_equal %i[expr labels record], recording_rule.keys.sort
    refute_includes recording_rule, :kind
    refute_includes recording_rule, :metric

    burn_rule = groups.fetch(2).fetch(:rules).fetch(0)
    assert_equal %i[expr labels record], burn_rule.keys.sort
    refute_includes burn_rule, :threshold

    alert_rule = groups.fetch(3).fetch(:rules).fetch(0)
    assert_equal %i[alert annotations expr for labels], alert_rule.keys.sort
    refute_includes alert_rule, :classification
  end

  def test_renders_grafana_sidecar_config_map
    artifacts = @provider.generate(@definition).to_h.fetch(:artifacts)
    resource = artifacts.fetch(:grafana_dashboard_resources).fetch(0)

    assert_equal 'v1', resource.fetch(:apiVersion)
    assert_equal 'ConfigMap', resource.fetch(:kind)
    assert_equal 'checkout-api-slo-dashboards', resource.fetch(:metadata).fetch(:name)
    assert_equal '1', resource.fetch(:metadata).fetch(:labels).fetch('grafana_dashboard')

    dashboard_json = resource.fetch(:data).fetch('checkout-api-slo.json')
    dashboard = JSON.parse(dashboard_json)
    assert_equal 'checkout-api-slo', dashboard.fetch('uid')
    assert_equal 'checkout-api SLO decision dashboard', dashboard.fetch('title')
    assert_equal 39, dashboard.fetch('schemaVersion')
    assert_equal %w[
      Success\ Ratio
      Error\ Ratio
      Error\ Budget\ Ratio
      Error\ Budget\ Remaining
      Burn\ Rate
      SLI\ Observations
    ], dashboard.fetch('panels').map { |panel| panel.fetch('title').split(' - ').last }
    dashboard.fetch('panels').each do |panel|
      assert_equal 'prometheus', panel.fetch('datasource').fetch('type')
      refute_empty panel.fetch('targets').fetch(0).fetch('expr')
    end
  end

  def test_renders_alertmanager_route_intent_without_inventing_receiver_credentials
    artifacts = @provider.generate(@definition).to_h.fetch(:artifacts)
    bundle = artifacts.fetch(:alertmanager_route_bundles).fetch(0)

    assert_equal 'slo-rules-engine/alertmanager-route-intent/v1', bundle.fetch(:version)
    assert_equal 'AlertmanagerRouteIntent', bundle.fetch(:kind)
    assert_equal 'checkout-api', bundle.fetch(:service)
    assert_equal true, bundle.fetch(:receiver_contract).fetch(:configuration_required)
    assert_equal '/api/alertmanager/:route_key', bundle.fetch(:receiver_contract).fetch(:endpoint_path)
    refute_includes bundle.fetch(:receiver_contract), :url
    assert_equal(
      {
        matchers: {
          service: 'checkout-api',
          route_key: 'checkout-api'
        },
        receiver: 'notification-router',
        webhook_path: '/api/alertmanager/checkout-api'
      },
      bundle.fetch(:routes).fetch(0)
    )
  end

  private

  def deep_copy(value)
    Marshal.load(Marshal.dump(value))
  end
end
