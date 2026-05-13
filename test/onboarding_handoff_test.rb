# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'tempfile'
require 'tmpdir'
require_relative '../lib/sre'

class OnboardingHandoffTest < Minitest::Test
  def test_review_records_acceptance_without_changing_candidate_evidence
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'checkout-prod.handoff.json')
      packet = handoff_packet
      File.write(path, JSON.pretty_generate(packet))

      result = SloRulesEngine::Onboarding::HandoffReviewer.new.review(
        path,
        accepted_candidate_uids: ['request-latency'],
        rejected_candidate_uids: ['request-traffic'],
        notes: ['Latency is the first onboarding SLO.']
      )

      updated = JSON.parse(File.read(path))
      assert_equal 'reviewed', updated.fetch('review').fetch('status')
      assert_equal ['request-latency'], updated.fetch('review').fetch('accepted_candidate_uids')
      assert_equal ['request-traffic'], updated.fetch('review').fetch('rejected_candidate_uids')
      assert_equal ['Latency is the first onboarding SLO.'], updated.fetch('review').fetch('notes')
      assert_equal packet.fetch(:candidate_review), symbolize(updated.fetch('candidate_review'))
      assert_equal ['request-latency'], result.fetch(:review).fetch(:accepted_candidate_uids)
    end
  end

  def test_review_rejects_unknown_candidate_uids
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'checkout-prod.handoff.json')
      File.write(path, JSON.pretty_generate(handoff_packet))

      error = assert_raises(SloRulesEngine::Onboarding::HandoffReviewer::ReviewError) do
        SloRulesEngine::Onboarding::HandoffReviewer.new.review(
          path,
          accepted_candidate_uids: ['missing-sli']
        )
      end

      assert_equal 'invalid_candidate_uid', error.code
      assert_includes error.message, 'missing-sli'
      assert_equal 'unreviewed', JSON.parse(File.read(path)).fetch('review').fetch('status')
    end
  end

  def test_draft_generation_uses_only_accepted_handoff_candidates
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'checkout-prod.handoff.json')
      File.write(path, JSON.pretty_generate(reviewed_handoff_packet))

      draft = SloRulesEngine::Onboarding::HandoffDraftGenerator.new.generate(
        path,
        service: 'checkout-api',
        owner: 'payments-platform'
      )

      assert_includes draft, '# Generated from reviewed onboarding handoff. Review before production use.'
      assert_includes draft, "uid 'request-latency'"
      assert_includes draft, '# review note: Latency is accepted for the first onboarding draft.'
      refute_includes draft, "uid 'request-traffic'"

      Tempfile.create(['handoff-draft', '.rb']) do |file|
        file.write(draft)
        file.flush

        SloRulesEngine.clear_definitions
        load file.path
        definition = SloRulesEngine.definitions.fetch(0)
        result = SloRulesEngine::CoreValidator.new.validate(definition)

        assert result.valid?, result.to_h.inspect
        assert_equal 'checkout-api', definition.service
        assert_equal 'request-latency', definition.slis.fetch(0).uid
      end
    end
  ensure
    SloRulesEngine.clear_definitions
  end

  def test_draft_generation_requires_reviewed_handoff
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'checkout-prod.handoff.json')
      File.write(path, JSON.pretty_generate(handoff_packet))

      error = assert_raises(SloRulesEngine::Onboarding::HandoffDraftGenerator::DraftError) do
        SloRulesEngine::Onboarding::HandoffDraftGenerator.new.generate(
          path,
          service: 'checkout-api',
          owner: 'payments-platform'
        )
      end

      assert_equal 'unreviewed_handoff', error.code
    end
  end

  private

  def handoff_packet
    {
      label: 'checkout-prod',
      provider: 'datadog',
      scope: { label: 'checkout-prod', service: 'checkout-api' },
      discovery: {
        signals: [{ kind: 'latency', metric: 'http.server.request.duration', user_visible: true }],
        findings: [],
        finding_codes: []
      },
      candidate_review: {
        candidates: [
          { sli_uid: 'request-latency', metric: 'http.server.request.duration', confidence: { level: 'high' } },
          { sli_uid: 'request-traffic', metric: 'http.server.requests', confidence: { level: 'medium' } }
        ],
        findings: []
      },
      review: {
        status: 'unreviewed',
        accepted_candidate_uids: [],
        rejected_candidate_uids: [],
        notes: []
      }
    }
  end

  def reviewed_handoff_packet
    packet = handoff_packet
    packet[:candidate_review] = {
      candidates: [
        candidate(
          sli_uid: 'request-latency',
          signal: 'latency',
          metric: 'http.server.request.duration',
          slo_uid: 'fast-enough'
        ),
        candidate(
          sli_uid: 'request-traffic',
          signal: 'traffic',
          metric: 'http.server.requests',
          slo_uid: 'healthy-enough'
        )
      ],
      findings: []
    }
    packet[:review] = {
      status: 'reviewed',
      accepted_candidate_uids: ['request-latency'],
      rejected_candidate_uids: ['request-traffic'],
      notes: ['Latency is accepted for the first onboarding draft.']
    }
    packet
  end

  def candidate(sli_uid:, signal:, metric:, slo_uid:)
    {
      sli_uid: sli_uid,
      signal: signal,
      metric: metric,
      rationale: 'Measured telemetry is close to user-visible service quality.',
      confidence: { level: 'high', score: 85, reasons: [], caveats: [] },
      explanation: "Metric #{metric} is proposed as #{sli_uid}.",
      evidence: { source: 'datadog' },
      calculation_basis_recommendation: nil,
      proposed_slo: {
        uid: slo_uid,
        objective: 0.99,
        success_condition: 'Observation meets the reviewed service quality threshold.',
        calculation_basis: 'observations'
      }
    }
  end

  def symbolize(value)
    case value
    when Hash
      value.transform_keys(&:to_sym).transform_values { |entry| symbolize(entry) }
    when Array
      value.map { |entry| symbolize(entry) }
    else
      value
    end
  end
end
