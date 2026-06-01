# frozen_string_literal: true

require 'json'

module OnboardingFixtures
  def write_discovery_fixture(dir)
    File.write(
      File.join(dir, 'checkout-prod.json'),
      JSON.pretty_generate(discovery_result_payload)
    )
    File.write(
      File.join(dir, 'index.json'),
      JSON.pretty_generate(discovery_index_payload)
    )
    File.join(dir, 'index.json')
  end

  def discovery_result_payload
    {
      provider: 'datadog',
      scope: { label: 'checkout-prod', service: 'checkout-api' },
      signals: [
        { kind: 'latency', metric: 'http.server.request.duration', user_visible: true, source: 'datadog' }
      ],
      findings: []
    }
  end

  def discovery_index_payload
    {
      provider: 'datadog',
      generated_at: '2026-05-13T09:00:00Z',
      total_scopes: 1,
      successful_scopes: 1,
      failed_scopes: 0,
      scopes: [
        { label: 'checkout-prod', scope: { label: 'checkout-prod', service: 'checkout-api' }, status: 'ok', result_file: 'checkout-prod.json', signal_count: 1, finding_count: 0 }
      ]
    }
  end

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
        handoff_candidate(
          sli_uid: 'request-latency',
          signal: 'latency',
          metric: 'http.server.request.duration',
          slo_uid: 'fast-enough'
        ),
        handoff_candidate(
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

  def handoff_candidate(sli_uid:, signal:, metric:, slo_uid:)
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
end
