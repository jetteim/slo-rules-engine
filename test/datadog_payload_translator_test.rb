# frozen_string_literal: true

require_relative 'support/datadog_apply_test_case'

class DatadogPayloadTranslatorTest < DatadogApplyTest
  def test_translates_and_resolves_burn_rate_monitor_payload
    translator = SloRulesEngine::Datadog::PayloadTranslator.new
    artifact = @manifest.fetch(:artifacts).fetch(:monitors).fetch(0)

    payload = translator.payload_for(@manifest, artifact, 'datadog.monitor', 'artifacts.monitors[0]')
    resolved_payload = translator.resolve(payload, 'checkout-api http-requests public-api successful-requests' => 'slo-123')

    assert_equal 'slo alert', resolved_payload.fetch(:type)
    assert_includes resolved_payload.fetch(:query),
                    'burn_rate("slo-123").over("30d").long_window("1h").short_window("5m") > 14.4'
    assert_includes resolved_payload.fetch(:tags), 'source_ref:artifacts.monitors.0'
  end
end
