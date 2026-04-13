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

        definition.notification_routes.each do |route|
          source = route.source.to_sym
          route_map[source] ||= {}
          route_map[source][route.key] = {
            provider: route.provider,
            target: route.target
          }
        end

        manifest(route_map: route_map)
      end
    end
  end
end
