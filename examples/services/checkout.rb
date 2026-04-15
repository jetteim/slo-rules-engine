# frozen_string_literal: true

require_relative '../../lib/sre'

SRE.define do
  service 'checkout-api'
  owner 'payments-platform'
  description 'Checkout API service level definition.'
  environments 'production'

  notification_route(
    key: 'checkout-api',
    source: 'datadog',
    provider: 'msteams',
    target: 'https://teams.microsoft.com/l/channel/example'
  )

  notification_route(
    key: 'checkout-api',
    source: 'alertmanager',
    provider: 'msteams',
    target: 'https://teams.microsoft.com/l/channel/example'
  )

  sli do
    uid 'http-requests'
    title 'HTTP requests'
    user_visible_rationale 'Represents whether customers can complete checkout requests.'

    measurement_details do
      source 'synthetic-otel-fixture'
      measurement_point 'server-side request boundary'
      threshold_requirements 'duration histogram with route and status dimensions'
      caveats 'synthetic example data only'
    end

    metric 'http.server.request.duration' do
      data_source 'otel'
      type 'counter'
      range '5m'
      selector service: 'checkout-api'

      provider_binding 'datadog' do
        metric 'http.server.request.duration'
        data_source 'datadog'
        type 'distribution'
        query 'p95:http.server.request.duration{service:checkout-api}'
      end

      provider_binding 'prometheus_stack' do
        metric 'http_server_request_duration_seconds_count'
        data_source 'prometheus'
        type 'counter'
        selector service: 'checkout-api'
      end
    end

    instance do
      uid 'public-api'
      selector route: '/checkout'
      playbook_url 'https://example.com/playbooks/checkout-api'
      dashboard_variables service: 'checkout-api'

      slo do
        uid 'successful-requests'
        objective 0.999
        success_selector status: 'success'
        calculation_basis 'observations'
        alert_route_key 'checkout-api'
        dashboard_path '/d/slo/checkout-api'
        documentation 'Requests complete without service-side failure.'
        miss_policy do
          trigger 'error budget exhausted'
          response 'assign one responder to restore service health'
          authority 'pause risky changes for the affected service'
          exit_condition 'burn rate returns below policy threshold'
          review_cadence 'next business day'
        end
        reality_check_notes 'synthetic example objective; replace with historical review before production use'
        observability_handoff 'bind provider queries', 'generate decision dashboard'
      end
    end
  end
end
