# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/slo_rules_engine'

class ManifestReviewQueueTest < Minitest::Test
  def test_report_flags_provenance_gaps_and_rolls_up_review_status
    report = SloRulesEngine::ManifestReviewQueue::ReportBuilder.new.build(
      [
        { service: 'checkout-api', provider: 'datadog' },
        {
          service: 'payments-api',
          provider: 'datadog',
          review_provenance: {
            label: 'payments-prod',
            provider: 'prometheus_stack',
            accepted_candidate_uids: []
          }
        },
        {
          service: 'catalog-api',
          provider: 'datadog',
          review_provenance: {
            label: 'catalog-prod',
            provider: 'datadog',
            accepted_candidate_uids: ['request-latency'],
            rejected_candidate_uids: ['request-traffic'],
            notes: ['Latency accepted.']
          }
        }
      ],
      provider: 'datadog'
    )

    refute report.fetch(:valid)
    assert_equal 3, report.fetch(:total_manifests)
    assert_equal 1, report.fetch(:summary).fetch(:reviewed_manifests)
    assert_equal 1, report.fetch(:summary).fetch(:missing_provenance_manifests)
    assert_equal 1, report.fetch(:summary).fetch(:incomplete_provenance_manifests)
    assert_equal 1, report.fetch(:summary).fetch(:accepted_candidate_total)
    assert_equal 1, report.fetch(:summary).fetch(:rejected_candidate_total)
    assert_equal 1, report.fetch(:summary).fetch(:note_total)

    manifests = report.fetch(:manifests)
    assert_equal 'missing_provenance', manifests.fetch(0).fetch(:status)
    assert_equal ['missing_review_provenance'], manifests.fetch(0).fetch(:findings).map { |finding| finding.fetch(:code) }
    assert_equal 'incomplete_provenance', manifests.fetch(1).fetch(:status)
    assert_equal %w[missing_accepted_candidate provenance_provider_mismatch], manifests.fetch(1).fetch(:findings).map { |finding| finding.fetch(:code) }
    assert_equal 'reviewed', manifests.fetch(2).fetch(:status)
    assert_empty manifests.fetch(2).fetch(:findings)
  end

  def test_report_links_findings_to_handoff_packet_paths
    Dir.mktmpdir do |dir|
      handoff_path = File.join(dir, 'payments-prod.handoff.json')
      File.write(handoff_path, JSON.pretty_generate(label: 'payments-prod'))

      report = SloRulesEngine::ManifestReviewQueue::ReportBuilder.new.build(
        [
          {
            service: 'payments-api',
            provider: 'datadog',
            review_provenance: {
              label: 'payments-prod',
              provider: 'datadog',
              accepted_candidate_uids: []
            }
          }
        ],
        provider: 'datadog',
        handoff_dir: dir
      )

      manifest = report.fetch(:manifests).fetch(0)
      assert_equal(
        {
          label: 'payments-prod',
          path: handoff_path,
          exists: true
        },
        manifest.fetch(:handoff)
      )
      finding = manifest.fetch(:findings).fetch(0)
      assert_equal 'payments-prod', finding.fetch(:handoff_label)
      assert_equal handoff_path, finding.fetch(:handoff_file)
    end
  end

  def test_report_flags_stale_provenance_against_reviewed_handoff
    Dir.mktmpdir do |dir|
      handoff_path = File.join(dir, 'checkout-prod.handoff.json')
      File.write(
        handoff_path,
        JSON.pretty_generate(
          label: 'checkout-prod',
          provider: 'datadog',
          review: {
            status: 'reviewed',
            accepted_candidate_uids: ['request-errors'],
            rejected_candidate_uids: ['request-latency'],
            notes: ['Errors accepted after review.']
          }
        )
      )

      report = SloRulesEngine::ManifestReviewQueue::ReportBuilder.new.build(
        [
          {
            service: 'checkout-api',
            provider: 'datadog',
            review_provenance: {
              label: 'checkout-prod',
              provider: 'datadog',
              accepted_candidate_uids: ['request-latency'],
              rejected_candidate_uids: ['request-traffic'],
              notes: ['Latency accepted first.']
            }
          }
        ],
        provider: 'datadog',
        handoff_dir: dir
      )

      refute report.fetch(:valid)
      assert_equal 1, report.fetch(:summary).fetch(:stale_provenance_manifests)
      manifest = report.fetch(:manifests).fetch(0)
      assert_equal 'stale_provenance', manifest.fetch(:status)
      assert_equal %w[
        stale_accepted_candidates
        stale_rejected_candidates
        stale_review_notes
      ], manifest.fetch(:findings).map { |finding| finding.fetch(:code) }
      assert_equal ['request-errors'], manifest.fetch(:findings).fetch(0).fetch(:expected)
      assert_equal ['request-latency'], manifest.fetch(:findings).fetch(0).fetch(:actual)
    end
  end

  def test_report_flags_missing_handoff_packet_when_handoff_dir_is_supplied
    Dir.mktmpdir do |dir|
      report = SloRulesEngine::ManifestReviewQueue::ReportBuilder.new.build(
        [
          {
            service: 'checkout-api',
            provider: 'datadog',
            review_provenance: {
              label: 'checkout-prod',
              provider: 'datadog',
              accepted_candidate_uids: ['request-latency']
            }
          }
        ],
        provider: 'datadog',
        handoff_dir: dir
      )

      refute report.fetch(:valid)
      assert_equal 1, report.fetch(:summary).fetch(:missing_handoff_manifests)
      manifest = report.fetch(:manifests).fetch(0)
      assert_equal 'missing_handoff', manifest.fetch(:status)
      assert_equal false, manifest.fetch(:handoff).fetch(:exists)
      assert_equal ['missing_handoff_packet'], manifest.fetch(:findings).map { |finding| finding.fetch(:code) }
    end
  end
end
