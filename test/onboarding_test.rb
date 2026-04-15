# frozen_string_literal: true

require 'minitest/autorun'
require 'tempfile'
require_relative '../lib/sre'

class OnboardingTest < Minitest::Test
  def test_generates_candidates_only_from_user_visible_telemetry
    generator = SloRulesEngine::Onboarding::CandidateGenerator.new

    candidates = generator.generate([
      {
        kind: 'latency',
        metric: 'http_request_duration_seconds',
        user_visible: true,
        objective: 0.95,
        observations_per_second: 10,
        failed_observations_to_alert: 100
      },
      { kind: 'saturation', metric: 'ruby_heap_slots', user_visible: false }
    ])

    assert_equal 1, candidates.length
    assert_equal 'request-latency', candidates.fetch(0)[:sli_uid]
    assert_equal 0.95, candidates.fetch(0)[:proposed_slo][:objective]
    assert_equal 'observations', candidates.fetch(0)[:proposed_slo][:calculation_basis]
  end

  def test_review_records_candidate_evidence_and_findings
    generator = SloRulesEngine::Onboarding::CandidateGenerator.new

    review = generator.review([
      {
        kind: 'availability',
        metric: 'http_requests_total',
        user_visible: true,
        observations_per_second: 0.01,
        failed_observations_to_alert: 1
      },
      { kind: 'saturation', metric: 'runtime_heap_used', user_visible: false },
      { kind: 'cache_hit_rate', metric: 'cache_hits_total', user_visible: true },
      { kind: 'errors', user_visible: true }
    ])

    assert_equal 1, review[:candidates].length
    assert_equal 'time_slice', review[:candidates].fetch(0)[:proposed_slo][:calculation_basis]
    assert_equal 0.01, review[:candidates].fetch(0)[:evidence][:observations_per_second]
    assert_equal 'high', review[:candidates].fetch(0)[:calculation_basis_recommendation][:confidence]

    assert_equal %w[non_user_visible unsupported_signal missing_metric], review[:findings].map { |finding| finding[:code] }
  end

  def test_generates_loadable_definition_draft_from_telemetry
    generator = SloRulesEngine::Onboarding::DefinitionDraftGenerator.new

    draft = generator.generate(
      service: 'checkout-api',
      owner: 'payments-platform',
      signals: [
        {
          kind: 'latency',
          metric: 'http.server.request.duration',
          user_visible: true,
          objective: 0.95,
          observations_per_second: 25,
          failed_observations_to_alert: 120
        },
        { kind: 'saturation', metric: 'runtime.heap.used', user_visible: false }
      ]
    )

    assert_includes draft, "service 'checkout-api'"
    assert_includes draft, "uid 'request-latency'"
    assert_includes draft, "metric 'http.server.request.duration'"
    assert_includes draft, "user_visible_rationale 'Measured telemetry is close to user-visible service quality.'"
    assert_includes draft, 'measurement_details do'
    assert_includes draft, 'miss_policy do'
    assert_includes draft, "observability_handoff 'bind provider queries', 'generate decision dashboard'"
    refute_includes draft, "uid 'resource-saturation'"
    assert_includes draft, '# finding: non_user_visible'

    Tempfile.create(['draft-definition', '.rb']) do |file|
      file.write(draft)
      file.flush

      SloRulesEngine.clear_definitions
      load file.path
      definition = SloRulesEngine.definitions.fetch(0)
      result = SloRulesEngine::CoreValidator.new.validate(definition)

      assert result.valid?, result.to_h.inspect
      assert_equal 'checkout-api', definition.service
      assert_equal 'request-latency', definition.slis.fetch(0).uid
      assert_equal 'fast-enough', definition.slis.fetch(0).instances.fetch(0).slos.fetch(0).uid
    end
  ensure
    SloRulesEngine.clear_definitions
  end
end
