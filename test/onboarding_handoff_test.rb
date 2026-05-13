# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/slo_rules_engine'

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
