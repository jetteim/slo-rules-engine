# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'tempfile'
require 'tmpdir'
require_relative '../lib/sre'
require_relative 'support/onboarding_fixtures'

class OnboardingHandoffTest < Minitest::Test
  include OnboardingFixtures

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
      assert_includes draft, '# handoff: checkout-prod provider=datadog'
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
        assert_equal 'checkout-prod', definition.review_provenance.label
        assert_equal 'datadog', definition.review_provenance.provider
        assert_equal ['request-latency'], definition.review_provenance.accepted_candidate_uids
        assert_equal ['Latency is accepted for the first onboarding draft.'], definition.review_provenance.notes
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

  def test_draft_generation_rejects_invalid_reviewed_handoff
    Dir.mktmpdir do |dir|
      packet = reviewed_handoff_packet
      packet.fetch(:candidate_review).fetch(:candidates).fetch(0).delete(:metric)
      path = File.join(dir, 'checkout-prod.handoff.json')
      File.write(path, JSON.pretty_generate(packet))

      error = assert_raises(SloRulesEngine::Onboarding::HandoffDraftGenerator::DraftError) do
        SloRulesEngine::Onboarding::HandoffDraftGenerator.new.generate(
          path,
          service: 'checkout-api',
          owner: 'payments-platform'
        )
      end

      assert_equal 'invalid_handoff', error.code
      assert_includes error.message, 'candidate_review.candidates[0].metric'
    end
  end

  def test_validation_accepts_reviewed_handoff_with_complete_accepted_candidates
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'checkout-prod.handoff.json')
      File.write(path, JSON.pretty_generate(reviewed_handoff_packet))

      result = SloRulesEngine::Onboarding::HandoffValidator.new.validate_file(path)

      assert result.valid?, result.to_h.inspect
      assert_equal 1, result.to_h.fetch(:accepted_candidate_count)
      assert_equal 'checkout-prod', result.to_h.fetch(:label)
    end
  end

  def test_validation_rejects_incomplete_accepted_candidates
    Dir.mktmpdir do |dir|
      packet = reviewed_handoff_packet
      packet.fetch(:candidate_review).fetch(:candidates).fetch(0).delete(:proposed_slo)
      path = File.join(dir, 'checkout-prod.handoff.json')
      File.write(path, JSON.pretty_generate(packet))

      result = SloRulesEngine::Onboarding::HandoffValidator.new.validate_file(path)

      refute result.valid?
      assert result.errors.any? { |error| error.path == 'candidate_review.candidates[0].proposed_slo' }
    end
  end

  private

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
