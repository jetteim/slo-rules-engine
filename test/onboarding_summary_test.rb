# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/slo_rules_engine'

class OnboardingSummaryTest < Minitest::Test
  def test_build_ranks_scopes_by_review_readiness
    Dir.mktmpdir do |dir|
      write_json(
        File.join(dir, 'checkout-prod.json'),
        provider: 'datadog',
        scope: { label: 'checkout-prod', service: 'checkout-api' },
        signals: [
          { kind: 'latency', metric: 'http.server.request.duration', user_visible: true, source: 'datadog' }
        ],
        findings: []
      )

      write_json(
        File.join(dir, 'payments-prod.json'),
        provider: 'datadog',
        scope: { label: 'payments-prod', selectors: { 'team' => 'payments' } },
        signals: [
          { kind: 'latency', metric: 'http.server.request.duration', user_visible: true, source: 'datadog' },
          { kind: 'saturation', metric: 'runtime.heap.used', user_visible: false, source: 'datadog' }
        ],
        findings: [{ code: 'sparse_telemetry', message: 'Only one user-journey metric found.' }]
      )

      write_json(
        File.join(dir, 'analytics-prod.json'),
        provider: 'datadog',
        scope: { label: 'analytics-prod', service: 'analytics-api' },
        signals: [
          { kind: 'saturation', metric: 'runtime.heap.used', user_visible: false, source: 'datadog' }
        ],
        findings: []
      )

      write_json(
        File.join(dir, 'index.json'),
        provider: 'datadog',
        generated_at: '2026-05-13T09:00:00Z',
        total_scopes: 4,
        successful_scopes: 3,
        failed_scopes: 1,
        scopes: [
          { label: 'checkout-prod', scope: { label: 'checkout-prod', service: 'checkout-api' }, status: 'ok', result_file: 'checkout-prod.json', signal_count: 1, finding_count: 0 },
          { label: 'payments-prod', scope: { label: 'payments-prod', selectors: { 'team' => 'payments' } }, status: 'ok', result_file: 'payments-prod.json', signal_count: 2, finding_count: 1 },
          { label: 'analytics-prod', scope: { label: 'analytics-prod', service: 'analytics-api' }, status: 'ok', result_file: 'analytics-prod.json', signal_count: 1, finding_count: 0 },
          { label: 'broken-scope', scope: { label: 'broken-scope', service: 'broken-api' }, status: 'error', signal_count: 0, finding_count: 0, error: { code: 'discovery_failed', message: 'timeout' } }
        ]
      )

      summary = SloRulesEngine::Onboarding::SummaryBuilder.new.build(File.join(dir, 'index.json'))

      assert_equal 'datadog', summary.fetch(:provider)
      assert_equal 4, summary.fetch(:total_scopes)
      assert_equal 1, summary.fetch(:summary).fetch(:ready_scopes)
      assert_equal 1, summary.fetch(:summary).fetch(:partial_scopes)
      assert_equal 1, summary.fetch(:summary).fetch(:insufficient_scopes)
      assert_equal 1, summary.fetch(:summary).fetch(:failed_scopes)

      ranked = summary.fetch(:scopes)
      assert_equal %w[checkout-prod payments-prod analytics-prod broken-scope], ranked.map { |scope| scope.fetch(:label) }
      assert_equal %w[ready partial insufficient failed], ranked.map { |scope| scope.fetch(:readiness) }
      assert_equal 1, ranked.first.fetch(:candidate_count)
      assert_equal ['sparse_telemetry', 'non_user_visible'], ranked.fetch(1).fetch(:finding_codes)
      assert_equal 'discovery_failed', ranked.last.fetch(:error).fetch(:code)
    end
  end

  def test_build_writes_saved_handoff_packets
    Dir.mktmpdir do |dir|
      write_json(
        File.join(dir, 'checkout-prod.json'),
        provider: 'datadog',
        scope: { label: 'checkout-prod', service: 'checkout-api' },
        signals: [
          {
            kind: 'latency',
            metric: 'http.server.request.duration',
            user_visible: true,
            source: 'datadog',
            observations_per_second: 25,
            failed_observations_to_alert: 120
          }
        ],
        findings: [{ code: 'discovery_note', message: 'Preserved discovery finding.' }]
      )

      write_json(
        File.join(dir, 'index.json'),
        provider: 'datadog',
        generated_at: '2026-05-13T09:00:00Z',
        total_scopes: 1,
        successful_scopes: 1,
        failed_scopes: 0,
        scopes: [
          { label: 'checkout-prod', scope: { label: 'checkout-prod', service: 'checkout-api' }, status: 'ok', result_file: 'checkout-prod.json', signal_count: 1, finding_count: 1 }
        ]
      )

      handoff_dir = File.join(dir, 'handoff')
      summary = SloRulesEngine::Onboarding::SummaryBuilder.new.build(File.join(dir, 'index.json'), handoff_dir: handoff_dir)
      scope = summary.fetch(:scopes).fetch(0)

      assert_equal File.join(handoff_dir, 'checkout-prod.handoff.json'), scope.fetch(:handoff_file)
      packet = JSON.parse(File.read(scope.fetch(:handoff_file)))
      assert_equal 'checkout-prod', packet.fetch('label')
      assert_equal 'datadog', packet.fetch('provider')
      assert_equal 'unreviewed', packet.fetch('review').fetch('status')
      assert_equal [], packet.fetch('review').fetch('accepted_candidate_uids')
      assert_equal ['discovery_note'], packet.fetch('discovery').fetch('finding_codes')
      assert_equal 'high', packet.fetch('candidate_review').fetch('candidates').fetch(0).fetch('confidence').fetch('level')
      assert_includes packet.fetch('handoff').fetch('required_review_steps'), 'accept or reject each candidate'
    end
  end

  private

  def write_json(path, payload)
    File.write(path, JSON.pretty_generate(payload))
  end
end
