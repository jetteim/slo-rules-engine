# frozen_string_literal: true

module SloRulesEngine
  module Providers
    class NotificationRouter < Provider
      def initialize
        super(
          key: 'notification_router',
          capabilities: %w[
            contextual_alerts
            notification_router_integration
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
