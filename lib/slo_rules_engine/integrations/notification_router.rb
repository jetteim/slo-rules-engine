# frozen_string_literal: true

module SloRulesEngine
  module Integrations
    class NotificationRouter < Integration
      def initialize
        super(
          key: 'notification_router',
          capabilities: %w[
            contextual_alert_delivery
            route_catalog_generation
            route_availability_checks
          ]
        )
      end

      def generate(definition)
        route_map = {
          datadog: {},
          alertmanager: {}
        }
        route_availability_checks = []

        definition.notification_routes.each do |route|
          source = route.source.to_sym
          route_map[source] ||= {}
          route_map[source][route.key] = {
            provider: route.provider,
            target: route.target
          }
          route_availability_checks << availability_check(definition, route)
        end

        manifest(
          route_map: route_map,
          route_availability_checks: route_availability_checks
        )
      end

      private

      def availability_check(definition, route)
        {
          source: route.source,
          route_key: route.key,
          method: 'GET',
          path: availability_path(definition, route)
        }
      end

      def availability_path(definition, route)
        case route.source.to_s
        when 'datadog' then "/api/datadog/#{definition.service}/#{route.key}"
        when 'alertmanager' then "/api/alertmanager/#{route.key}"
        else "/api/routes/#{route.source}/#{route.key}"
        end
      end
    end
  end
end
