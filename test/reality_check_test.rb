# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/slo_rules_engine'

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
end
