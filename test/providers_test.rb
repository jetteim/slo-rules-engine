# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/sre'

class ProvidersTest < Minitest::Test
  def setup
    SloRulesEngine.clear_definitions
    load File.expand_path('../examples/services/checkout.rb', __dir__)
    @definition = SloRulesEngine.definitions.fetch(0)
  end

  def test_lists_complete_backend_providers
    registry = SloRulesEngine.default_provider_registry

    assert_equal %w[datadog prometheus_stack], registry.list.map(&:key)
    assert_includes registry.fetch('prometheus_stack').capabilities, 'parameterized_dashboards'
    assert_includes registry.fetch('datadog').capabilities, 'slo_evaluation'
  end

  def test_datadog_provider_generates_slo_monitor_and_dashboard
    manifest = SloRulesEngine.default_provider_registry.fetch('datadog').generate(@definition).to_h

    assert_equal 'datadog', manifest[:provider]
    assert_equal 1, manifest[:artifacts][:slos].length
    assert_equal 1, manifest[:artifacts][:monitors].length
    assert_equal 1, manifest[:artifacts][:dashboards].length
  end

  def test_prometheus_stack_provider_is_single_bundle
    manifest = SloRulesEngine.default_provider_registry.fetch('prometheus_stack').generate(@definition).to_h

    assert_equal 'prometheus_stack', manifest[:provider]
    assert_equal 1, manifest[:artifacts][:recording_rules].length
    assert_equal 1, manifest[:artifacts][:alert_rules].length
    assert_equal 1, manifest[:artifacts][:alertmanager_routes].length
    assert_equal 1, manifest[:artifacts][:grafana_dashboards].length
  end

  def test_notification_router_integration_generates_route_catalog
    registry = SloRulesEngine.default_integration_registry
    manifest = registry.fetch('notification_router').generate(@definition).to_h

    assert_equal 'notification_router', manifest[:integration]
    assert_equal 'msteams', manifest[:artifacts][:route_map][:datadog]['checkout-api'][:provider]
    assert_equal 'msteams', manifest[:artifacts][:route_map][:alertmanager]['checkout-api'][:provider]
  end
end
