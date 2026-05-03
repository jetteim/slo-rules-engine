# frozen_string_literal: true

module SloRulesEngine
  module Providers
    class PrometheusStack < Provider
      def initialize
        super(
          key: 'prometheus_stack',
          capabilities: %w[
            sli_query_binding
            slo_evaluation
            burn_rate_alerting
            missing_telemetry_detection
            contextual_alerts
            notification_router_integration
            parameterized_dashboards
            reality_check
            apply_plan
          ],
          automation_mode: 'manifest_bundle',
          state_actions: %w[plan apply diff import_existing]
        )
      end

      def generate(definition)
        artifacts = {
          recording_rules: [],
          burn_rate_rules: [],
          missing_telemetry_rules: [],
          alert_rules: [],
          alertmanager_routes: [],
          grafana_dashboards: []
        }

        each_slo(definition) do |sli, instance, slo|
          artifacts[:recording_rules] << recording_rule(definition, sli, instance, slo)
          artifacts[:burn_rate_rules].concat(burn_rate_rules(definition, sli, instance, slo))
          artifacts[:missing_telemetry_rules] << missing_telemetry_rule(definition, sli, instance, slo)
          artifacts[:alert_rules] << burn_rate_alert(definition, sli, instance, slo)
          artifacts[:alertmanager_routes] << alertmanager_route(definition, slo)
          artifacts[:grafana_dashboards] << grafana_dashboard(definition, sli, instance, slo)
        end

        manifest(artifacts)
      end

      private

      def supported_data_sources
        %w[prometheus openmetrics]
      end

      def required_route_sources
        %w[alertmanager]
      end

      def each_slo(definition)
        definition.slis.each do |sli|
          sli.instances.each do |instance|
            instance.slos.each { |slo| yield sli, instance, slo }
          end
        end
      end

      def recording_rule(definition, sli, instance, slo)
        labels = prometheus_labels(definition, sli, instance, slo)
        {
          record: "slo:#{definition.service}:#{sli.uid}:#{instance.uid}:#{slo.uid}:success_ratio",
          labels: labels,
          expr: success_ratio_expression(sli.metric.binding_for(key), instance, slo)
        }
      end

      def burn_rate_rules(definition, sli, instance, slo)
        BurnRatePolicy.new.windows.map do |window|
          {
            record: "slo:#{definition.service}:#{sli.uid}:#{instance.uid}:#{slo.uid}:burn_rate:#{window[:range]}",
            labels: prometheus_labels(definition, sli, instance, slo),
            range: window[:range],
            percent: window[:percent],
            threshold: window[:threshold],
            expr: "(1 - slo:#{definition.service}:#{sli.uid}:#{instance.uid}:#{slo.uid}:success_ratio) / #{error_budget(slo)}"
          }
        end
      end

      def missing_telemetry_rule(definition, sli, instance, slo)
        labels = prometheus_labels(definition, sli, instance, slo).merge(
          severity: 'notification',
          route_key: slo.alert_route_key || definition.service
        )
        {
          alert: 'SLOTelemetryMissing',
          classification: 'notification',
          labels: labels,
          annotations: {
            summary: "#{definition.service} SLO telemetry is missing",
            service: definition.service,
            owner: definition.owner,
            sli: sli.uid,
            slo: slo.uid,
            dashboard: slo.dashboard_path || grafana_dashboard_path(definition, sli, instance, slo),
            playbook: instance.playbook_url
          },
          expr: "absent(#{sli.metric.binding_for(key).metric})",
          for: '10m'
        }
      end

      def burn_rate_alert(definition, sli, instance, slo)
        labels = prometheus_labels(definition, sli, instance, slo).merge(
          severity: 'page',
          route_key: slo.alert_route_key || definition.service
        )
        fast_window = BurnRatePolicy.new.windows.fetch(0)
        {
          alert: 'SLOErrorBudgetBurning',
          labels: labels,
          annotations: {
            summary: "#{definition.service} is burning error budget",
            service: definition.service,
            owner: definition.owner,
            sli: sli.uid,
            slo: slo.uid,
            dashboard: slo.dashboard_path || grafana_dashboard_path(definition, sli, instance, slo),
            playbook: instance.playbook_url
          },
          expr: "slo:#{definition.service}:#{sli.uid}:#{instance.uid}:#{slo.uid}:burn_rate:#{fast_window[:range]} > #{fast_window[:threshold]}",
          for: '5m'
        }
      end

      def alertmanager_route(definition, slo)
        {
          matchers: {
            service: definition.service,
            route_key: slo.alert_route_key || definition.service
          },
          receiver: 'notification-router'
        }
      end

      def grafana_dashboard(definition, sli, instance, slo)
        {
          title: "#{definition.service} SLO decision dashboard",
          path: grafana_dashboard_path(definition, sli, instance, slo),
          variables: {
            'service' => definition.service,
            'sli' => sli.uid,
            'sli_instance' => instance.uid,
            'slo' => slo.uid
          }.merge(instance.dashboard_variables),
          panels: %w[current_status burn_rate error_budget latency errors traffic]
        }
      end

      def success_ratio_expression(metric, instance, slo)
        selector = metric.selector.merge(instance.selector)
        labels = selector.map { |key, value| "#{key}=#{value.inspect}" }.join(',')
        if slo.success_selector
          success = selector.merge(slo.success_selector).map { |key, value| "#{key}=#{value.inspect}" }.join(',')
          "sum(rate(#{metric.metric}{#{success}}[#{metric.range || '5m'}])) / sum(rate(#{metric.metric}{#{labels}}[#{metric.range || '5m'}]))"
        else
          "#{metric.metric}{#{labels}}"
        end
      end

      def prometheus_labels(definition, sli, instance, slo)
        {
          service: definition.service,
          owner: definition.owner,
          sli: sli.uid,
          sli_instance: instance.uid,
          slo: slo.uid,
          objective_ratio: slo.objective.to_s,
          calculation_basis: slo.calculation_basis
        }
      end

      def grafana_dashboard_path(definition, sli, instance, slo)
        "/d/slo/#{definition.service}?var-sli=#{sli.uid}&var-instance=#{instance.uid}&var-slo=#{slo.uid}"
      end

      def error_budget(slo)
        1.0 - slo.objective.to_f
      end
    end
  end
end
