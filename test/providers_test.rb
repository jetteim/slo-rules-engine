# frozen_string_literal: true

require 'minitest/autorun'
require 'tempfile'
require_relative '../lib/sre'

class ProvidersTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

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
    assert_includes registry.fetch('prometheus_stack').capabilities, 'live_slo_status'
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

  def test_provider_contract_requires_required_capabilities_for_non_manifest_only_providers
    error = assert_raises(SloRulesEngine::ProviderContractError) do
      SloRulesEngine::Provider.new(
        key: 'broken',
        capabilities: %w[sli_query_binding slo_evaluation],
        automation_mode: 'live_api',
        state_actions: %w[plan apply diff import_existing prune]
      )
    end

    assert_includes error.message, 'missing required capabilities'
    assert_includes error.message, 'apply_plan'
  end

  def test_provider_contract_requires_all_state_actions_for_non_manifest_only_providers
    error = assert_raises(SloRulesEngine::ProviderContractError) do
      SloRulesEngine::Provider.new(
        key: 'broken',
        capabilities: production_capabilities,
        automation_mode: 'live_api',
        state_actions: %w[plan apply]
      )
    end

    assert_includes error.message, 'missing required state actions'
    assert_includes error.message, 'diff'
    assert_includes error.message, 'prune'
  end

  def test_datadog_provider_generates_slo_monitor_and_dashboard
    manifest = SloRulesEngine.default_provider_registry.fetch('datadog').generate(@definition).to_h

    assert_equal 'datadog', manifest[:provider]
    assert_equal 1, manifest[:artifacts][:slos].length
    assert_equal '30d', manifest[:artifacts][:slos].fetch(0).fetch(:evaluation_window)
    assert_equal '5m', manifest[:artifacts][:slos].fetch(0).fetch(:query).fetch(:range)
    assert_equal 1, manifest[:artifacts][:monitors].length
    assert_equal [14.4, 6.0], manifest[:artifacts][:monitors].fetch(0)[:burn_rate_windows].map { |window| window[:threshold] }
    assert_equal 1, manifest[:artifacts][:telemetry_gap_monitors].length
    assert_equal 'notification', manifest[:artifacts][:telemetry_gap_monitors].fetch(0)[:classification]
    assert_equal 1, manifest[:artifacts][:dashboards].length
  end

  def test_datadog_provider_rejects_evaluation_windows_outside_the_verified_contract
    slo = @definition.slis.fetch(0).instances.fetch(0).slos.fetch(0)
    slo.evaluation_window = '7d'

    result = SloRulesEngine.default_provider_registry.fetch('datadog').validate(@definition)

    refute result.valid?
    assert result.errors.any? do |error|
      error.path.end_with?('.evaluation_window') && error.message.include?('30d')
    end
  end

  def test_prometheus_stack_provider_is_single_bundle
    manifest = SloRulesEngine.default_provider_registry.fetch('prometheus_stack').generate(@definition).to_h

    assert_equal 'prometheus_stack', manifest[:provider]
    assert_equal 6, manifest[:artifacts][:recording_rules].length
    assert_equal 1, manifest[:artifacts][:recording_rules].count { |rule| rule[:kind] == 'sli' }
    assert_equal 5, manifest[:artifacts][:recording_rules].count { |rule| rule[:kind] == 'slo' }
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

  def test_provider_manifests_preserve_reviewed_handoff_provenance
    definition = reviewed_handoff_definition

    SloRulesEngine.default_provider_registry.list.each do |provider|
      manifest = provider.generate(definition).to_h
      provenance = manifest.fetch(:review_provenance)

      assert_equal 'checkout-prod', provenance.fetch(:label)
      assert_equal 'datadog', provenance.fetch(:provider)
      assert_equal ['request-latency'], provenance.fetch(:accepted_candidate_uids)
      assert_equal ['Latency accepted.'], provenance.fetch(:notes)
    end
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

  private

  def production_capabilities
    %w[
      sli_query_binding
      slo_evaluation
      burn_rate_alerting
      missing_telemetry_detection
      contextual_alerts
      notification_router_integration
      parameterized_dashboards
      reality_check
      apply_plan
    ]
  end

  def reviewed_handoff_definition
    load_string(<<~RUBY)
      SRE.define do
        service 'checkout-api'
        owner 'payments-platform'
        review_provenance label: 'checkout-prod',
                          provider: 'datadog',
                          accepted_candidate_uids: ['request-latency'],
                          notes: ['Latency accepted.']

        notification_route key: 'checkout-api', source: 'datadog', provider: 'msteams', target: '#checkout'
        notification_route key: 'checkout-api', source: 'alertmanager', provider: 'msteams', target: '#checkout'

        sli do
          uid 'request-latency'
          title 'Request Latency'
          user_visible_rationale 'Measured telemetry is close to user-visible service quality.'

          measurement_details do
            source 'datadog'
            measurement_point 'service request boundary'
            threshold_requirements 'review histogram units, buckets, and threshold before production use'
            caveats 'generated draft; confirm telemetry represents user-visible service quality'
          end

          metric 'http.server.request.duration' do
            data_source 'telemetry-inventory'
            type 'histogram'
            selector service: 'checkout-api'
            provider_binding 'datadog' do
              metric 'http.server.request.duration'
              data_source 'datadog'
              type 'distribution'
              selector service: 'checkout-api'
              query 'p95:http.server.request.duration{service:checkout-api}'
            end
            provider_binding 'prometheus_stack' do
              metric 'http_server_request_duration_seconds_count'
              data_source 'prometheus'
              type 'counter'
              range '5m'
              selector service: 'checkout-api'
            end
            provider_binding 'sloth' do
              metric 'http_server_request_duration_seconds_count'
              data_source 'prometheus'
              type 'counter'
              range '5m'
              selector service: 'checkout-api'
            end
          end

          instance do
            uid 'default'
            slo do
              uid 'fast-enough'
              objective 0.99
              success_threshold '<=', 'user-reviewed latency threshold'
              calculation_basis 'observations'
              documentation 'Observation meets the reviewed service quality threshold.'
              miss_policy do
                trigger 'error budget exhausted'
                response 'review generated SLO, assign responder, and restore service health'
                authority 'pause risky changes for the affected service'
                exit_condition 'burn rate returns below reviewed policy threshold'
              end
              observability_handoff 'bind provider queries', 'generate decision dashboard'
            end
          end
        end
      end
    RUBY

    SloRulesEngine.definitions.last
  end

  def load_string(source)
    Tempfile.create(['definition', '.rb']) do |file|
      file.write("require_relative '#{ROOT}/lib/sre'\n")
      file.write(source)
      file.flush
      load file.path
    end
  end
end
