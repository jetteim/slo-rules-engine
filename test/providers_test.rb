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

    assert_equal %w[datadog prometheus_stack sloth], registry.list.map(&:key)
    assert_includes registry.fetch('prometheus_stack').capabilities, 'parameterized_dashboards'
    assert_includes registry.fetch('datadog').capabilities, 'slo_evaluation'
    assert_includes registry.fetch('datadog').capabilities, 'apply_plan'
    assert_includes registry.fetch('sloth').capabilities, 'slo_evaluation'
    assert_includes registry.fetch('sloth').capabilities, 'apply_plan'
  end

  def test_provider_registry_lists_automation_modes_and_state_actions
    providers = SloRulesEngine.default_provider_registry.list.to_h do |provider|
      [provider.key, { automation_mode: provider.automation_mode, state_actions: provider.state_actions }]
    end

    assert_equal 'live_api', providers.fetch('datadog').fetch(:automation_mode)
    assert_includes providers.fetch('datadog').fetch(:state_actions), 'apply'
    assert_includes providers.fetch('datadog').fetch(:state_actions), 'diff'
    assert_includes providers.fetch('datadog').fetch(:state_actions), 'import_existing'
    assert_includes providers.fetch('datadog').fetch(:state_actions), 'prune'
    assert_equal 'manifest_bundle', providers.fetch('prometheus_stack').fetch(:automation_mode)
    assert_includes providers.fetch('prometheus_stack').fetch(:state_actions), 'apply'
    assert_includes providers.fetch('prometheus_stack').fetch(:state_actions), 'diff'
    assert_includes providers.fetch('prometheus_stack').fetch(:state_actions), 'import_existing'
    assert_includes providers.fetch('prometheus_stack').fetch(:state_actions), 'prune'
    assert_equal 'external_generator', providers.fetch('sloth').fetch(:automation_mode)
    assert_includes providers.fetch('sloth').fetch(:state_actions), 'apply'
    assert_includes providers.fetch('sloth').fetch(:state_actions), 'diff'
    assert_includes providers.fetch('sloth').fetch(:state_actions), 'import_existing'
    assert_includes providers.fetch('sloth').fetch(:state_actions), 'prune'
  end

  def test_datadog_provider_generates_slo_monitor_and_dashboard
    manifest = SloRulesEngine.default_provider_registry.fetch('datadog').generate(@definition).to_h

    assert_equal 'datadog', manifest[:provider]
    assert_equal 1, manifest[:artifacts][:slos].length
    assert_equal 1, manifest[:artifacts][:monitors].length
    assert_equal [14.4, 6.0], manifest[:artifacts][:monitors].fetch(0)[:burn_rate_windows].map { |window| window[:threshold] }
    assert_equal 1, manifest[:artifacts][:telemetry_gap_monitors].length
    assert_equal 'notification', manifest[:artifacts][:telemetry_gap_monitors].fetch(0)[:classification]
    assert_equal 1, manifest[:artifacts][:dashboards].length
  end

  def test_prometheus_stack_provider_is_single_bundle
    manifest = SloRulesEngine.default_provider_registry.fetch('prometheus_stack').generate(@definition).to_h

    assert_equal 'prometheus_stack', manifest[:provider]
    assert_equal 1, manifest[:artifacts][:recording_rules].length
    assert_equal 2, manifest[:artifacts][:burn_rate_rules].length
    assert_equal [14.4, 6.0], manifest[:artifacts][:burn_rate_rules].map { |rule| rule[:threshold] }
    assert_equal 1, manifest[:artifacts][:missing_telemetry_rules].length
    assert_equal 'notification', manifest[:artifacts][:missing_telemetry_rules].fetch(0)[:classification]
    assert_equal 1, manifest[:artifacts][:alert_rules].length
    assert_equal 1, manifest[:artifacts][:alertmanager_routes].length
    assert_equal 1, manifest[:artifacts][:grafana_dashboards].length
  end

  def test_sloth_provider_generates_prometheus_v1_slo_spec
    manifest = SloRulesEngine.default_provider_registry.fetch('sloth').generate(@definition).to_h
    spec = manifest[:artifacts][:sloth_specs].fetch(0)
    slo = spec[:slos].fetch(0)

    assert_equal 'sloth', manifest[:provider]
    assert_equal 'prometheus/v1', spec[:version]
    assert_equal 'checkout-api', spec[:service]
    assert_equal({ owner: 'payments-platform' }, spec[:labels])
    assert_equal 'http-requests-public-api-successful-requests', slo[:name]
    assert_equal 99.9, slo[:objective]
    assert_equal 'Requests complete without service-side failure.', slo[:description]
    assert_includes slo[:sli][:events][:total_query], 'http_server_request_duration_seconds_count'
    assert_includes slo[:sli][:events][:error_query], 'status!="success"'
    assert_equal 'checkout-api', slo[:alerting][:page_alert][:labels][:routing_key]
  end

  def test_notification_router_integration_generates_route_catalog
    registry = SloRulesEngine.default_integration_registry
    manifest = registry.fetch('notification_router').generate(@definition).to_h

    assert_equal 'notification_router', manifest[:integration]
    assert_equal 'msteams', manifest[:artifacts][:route_map][:datadog]['checkout-api'][:provider]
    assert_equal 'msteams', manifest[:artifacts][:route_map][:alertmanager]['checkout-api'][:provider]
    assert_equal 2, manifest[:artifacts][:route_availability_checks].length
    assert_equal '/api/datadog/checkout-api/checkout-api', manifest[:artifacts][:route_availability_checks].fetch(0)[:path]
    assert_equal '/api/alertmanager/checkout-api', manifest[:artifacts][:route_availability_checks].fetch(1)[:path]
  end

  def test_provider_validation_requires_matching_route_source
    @definition.notification_routes.delete_if { |route| route.source == 'datadog' }

    result = SloRulesEngine.default_provider_registry.fetch('datadog').validate(@definition)

    refute result.valid?
    assert result.errors.any? { |error| error.path == 'notification_routes' && error.message.include?('datadog') }
  end
end
