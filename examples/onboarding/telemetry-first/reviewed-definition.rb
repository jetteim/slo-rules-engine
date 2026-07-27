# frozen_string_literal: true

require_relative '../../../lib/sre'

SRE.define do
  service 'checkout-api'
  owner 'payments-platform'
  description 'Reviewed telemetry-first onboarding definition.'
  environments 'production'

  review_provenance label: 'checkout-prod',
                    provider: 'datadog',
                    accepted_candidate_uids: ['request-latency'],
                    rejected_candidate_uids: ['request-traffic'],
                    notes: ['Latency accepted for the walkthrough.']

  notification_route(
    key: 'checkout-api',
    source: 'datadog',
    provider: 'msteams',
    target: 'https://teams.microsoft.com/l/channel/example'
  )

  sli do
    uid 'request-latency'
    title 'Request Latency'
    user_visible_rationale 'Measured telemetry is close to user-visible service quality.'

    measurement_details do
      source 'datadog'
      measurement_point 'service request boundary'
      threshold_requirements 'review histogram units, buckets, and threshold before production use'
      caveats 'representative public-safe walkthrough fixture'
    end

    metric 'http.server.request.duration' do
      data_source 'telemetry-inventory'
      type 'histogram'
      selector service: 'checkout-api'

      provider_binding 'datadog' do
        metric 'http.server.request.duration'
        data_source 'datadog'
        type 'distribution'
        selector service: 'checkout-api'
        query 'p95:http.server.request.duration{service:checkout-api}'
      end
    end

    instance do
      uid 'default'
      selector route: '/checkout'
      dashboard_variables service: 'checkout-api'

      slo do
        uid 'fast-enough'
        objective 0.99
        evaluation_window '30d'
        success_threshold '<=', '0.5'
        calculation_basis 'time_slice'
        alert_route_key 'checkout-api'
        dashboard_path '/d/slo/checkout-api'
        documentation 'Checkout request latency remains within the reviewed threshold.'
        miss_policy do
          trigger 'error budget exhausted'
          response 'review generated SLO, assign responder, and restore service health'
          authority 'pause risky changes for the affected service'
          exit_condition 'burn rate returns below reviewed policy threshold'
          review_cadence 'next business day'
        end
        reality_check_notes 'representative public-safe threshold; replace with historical review before production use'
        observability_handoff 'bind provider queries', 'generate decision dashboard'
      end
    end
  end
end
