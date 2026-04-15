# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/sre'

class ProviderBindingsTest < Minitest::Test
  def setup
    SloRulesEngine.clear_definitions
    load File.expand_path('../examples/services/checkout.rb', __dir__)
    @definition = SloRulesEngine.definitions.fetch(0)
  end

  def test_metric_can_define_provider_specific_query_bindings
    metric = @definition.slis.fetch(0).metric

    assert_equal 'http.server.request.duration', metric.binding_for('datadog').metric
    assert_equal 'http_server_request_duration_seconds_count', metric.binding_for('prometheus_stack').metric
    assert_equal 'http_server_request_duration_seconds_count', metric.binding_for('sloth').metric
  end

  def test_datadog_provider_uses_datadog_binding
    manifest = SloRulesEngine.default_provider_registry.fetch('datadog').generate(@definition).to_h
    query = manifest[:artifacts][:slos].fetch(0)[:query]

    assert_equal 'datadog', query[:data_source]
    assert_equal 'http.server.request.duration', query[:metric]
  end

  def test_prometheus_stack_provider_uses_prometheus_binding
    manifest = SloRulesEngine.default_provider_registry.fetch('prometheus_stack').generate(@definition).to_h
    rule = manifest[:artifacts][:recording_rules].fetch(0)

    assert_includes rule[:expr], 'http_server_request_duration_seconds_count'
  end

  def test_sloth_provider_uses_sloth_binding
    manifest = SloRulesEngine.default_provider_registry.fetch('sloth').generate(@definition).to_h
    slo = manifest[:artifacts][:sloth_specs].fetch(0)[:slos].fetch(0)

    assert_includes slo[:sli][:events][:total_query], 'http_server_request_duration_seconds_count'
  end

  def test_provider_validation_reports_missing_binding
    metric = @definition.slis.fetch(0).metric
    metric.provider_bindings.delete('datadog')

    result = SloRulesEngine.default_provider_registry.fetch('datadog').validate(@definition)

    refute result.valid?
    assert result.errors.any? { |error| error.message.include?('missing datadog query binding') }
  end

  def test_provider_validation_reports_unsupported_data_source
    binding = @definition.slis.fetch(0).metric.binding_for('datadog')
    binding.data_source = 'prometheus'

    result = SloRulesEngine.default_provider_registry.fetch('datadog').validate(@definition)

    refute result.valid?
    assert result.errors.any? { |error| error.message.include?('unsupported data source') }
  end
end
