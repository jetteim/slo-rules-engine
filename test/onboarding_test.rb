# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/slo_rules_engine'

class OnboardingTest < Minitest::Test
  def test_generates_candidates_only_from_user_visible_telemetry
    generator = SloRulesEngine::Onboarding::CandidateGenerator.new

    candidates = generator.generate([
      { kind: 'latency', metric: 'http_request_duration_seconds', user_visible: true, objective: 0.95 },
      { kind: 'saturation', metric: 'ruby_heap_slots', user_visible: false }
    ])

    assert_equal 1, candidates.length
    assert_equal 'request-latency', candidates.fetch(0)[:sli_uid]
    assert_equal 0.95, candidates.fetch(0)[:proposed_slo][:objective]
  end
end
