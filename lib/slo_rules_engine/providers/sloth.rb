# frozen_string_literal: true

module SloRulesEngine
  module Providers
    class Sloth < Provider
      def initialize
        super(
          key: 'sloth',
          capabilities: %w[
            sli_query_binding
            slo_evaluation
            burn_rate_alerting
            missing_telemetry_detection
            contextual_alerts
            notification_router_integration
            parameterized_dashboards
            reality_check
          ],
          automation_mode: 'external_generator',
          state_actions: %w[plan apply]
        )
      end

      def generate(definition)
        manifest(sloth_specs: [sloth_spec(definition)])
      end

      private

      def supported_data_sources
        %w[prometheus openmetrics]
      end

      def required_route_sources
        %w[alertmanager]
      end

      def sloth_spec(definition)
        {
          version: 'prometheus/v1',
          service: definition.service,
          labels: {
            owner: definition.owner
          },
          slos: slos(definition)
        }
      end

      def slos(definition)
        entries = []
        each_slo(definition) do |sli, instance, slo|
          entries << sloth_slo(definition, sli, instance, slo)
        end
        entries
      end

      def sloth_slo(definition, sli, instance, slo)
        {
          name: "#{sli.uid}-#{instance.uid}-#{slo.uid}",
          objective: objective_percent(slo),
          description: slo.documentation,
          sli: {
            events: event_queries(sli.metric.binding_for(key), instance, slo)
          },
          alerting: alerting(definition, sli, instance, slo)
        }
      end

      def event_queries(metric, instance, slo)
        {
          error_query: rate_query(metric, instance, slo.success_selector || {}),
          total_query: rate_query(metric, instance, {})
        }
      end

      def rate_query(metric, instance, negative_selector)
        selector = metric.selector.merge(instance.selector)
        labels = label_matchers(selector) + negative_label_matchers(negative_selector)
        "sum(rate(#{metric.metric}{#{labels.join(',')}}[#{metric.range || '5m'}]))"
      end

      def label_matchers(selector)
        selector.map { |key, value| "#{key}=#{quote_label(value)}" }
      end

      def negative_label_matchers(selector)
        selector.map { |key, value| "#{key}!=#{quote_label(value)}" }
      end

      def quote_label(value)
        value.to_s.inspect
      end

      def objective_percent(slo)
        (slo.objective.to_f * 100).round(6)
      end

      def alerting(definition, sli, instance, slo)
        route_key = slo.alert_route_key || definition.service
        {
          name: alert_name(definition, sli, instance, slo),
          labels: {
            owner: definition.owner,
            route_key: route_key
          },
          annotations: {
            summary: "#{definition.service} #{sli.uid} error budget is burning",
            service: definition.service,
            sli: sli.uid,
            slo: slo.uid,
            dashboard: slo.dashboard_path,
            playbook: instance.playbook_url,
            miss_policy: slo.miss_policy&.trigger
          }.compact,
          page_alert: {
            labels: {
              severity: 'page',
              routing_key: route_key
            }
          },
          ticket_alert: {
            labels: {
              severity: 'notification',
              routing_key: route_key
            }
          }
        }
      end

      def alert_name(definition, sli, instance, slo)
        [definition.service, sli.uid, instance.uid, slo.uid, 'burn'].map { |part| camelize(part) }.join
      end

      def camelize(value)
        value.to_s.split(/[^a-zA-Z0-9]/).reject(&:empty?).map(&:capitalize).join
      end
    end
  end
end
