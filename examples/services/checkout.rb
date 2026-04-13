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

    metric 'http_server_request_duration_seconds_count' do
      data_source 'prometheus'
      type 'counter'
      range '5m'
      selector service: 'checkout-api'
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
      end
    end
  end
end
