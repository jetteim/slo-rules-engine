# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/sre'

class ReliabilityModelTest < Minitest::Test
  def test_measurement_details_are_serializable
    details = SloRulesEngine::MeasurementDetails.new(
      source: 'synthetic-metrics',
      measurement_point: 'server-side request boundary',
      caveats: ['synthetic fixture']
    )

    assert_equal(
      {
        source: 'synthetic-metrics',
        measurement_point: 'server-side request boundary',
        probe_interval: nil,
        probe_timeout: nil,
        threshold_requirements: [],
        excluded_traffic: [],
        caveats: ['synthetic fixture']
      },
      details.to_h
    )
  end

  def test_miss_policy_has_required_review_shape
    policy = SloRulesEngine::MissPolicy.new(
      trigger: 'error budget exhausted',
      response: 'assign one responder to restore service health',
      authority: 'pause risky changes for the affected service',
      exit_condition: 'SLO burn rate returns below policy threshold',
      review_cadence: 'next business day'
    )

    assert_equal 'error budget exhausted', policy.to_h.fetch(:trigger)
    assert_equal 'next business day', policy.to_h.fetch(:review_cadence)
  end
end
