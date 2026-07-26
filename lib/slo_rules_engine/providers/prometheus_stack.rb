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
          state_actions: %w[plan apply diff import_existing prune]
        )
      end

      def generate(definition)
        artifacts = {
          recording_rules: [],
          burn_rate_rules: [],
          missing_telemetry_rules: [],
          alert_rules: [],
          alertmanager_routes: [],
          grafana_dashboards: [],
          prometheus_rule_resources: [],
          grafana_dashboard_resources: [],
          alertmanager_route_bundles: []
        }

        each_sli_instance(definition) do |sli, instance|
          artifacts[:recording_rules] << sli_recording_rule(definition, sli, instance)
          instance.slos.each do |slo|
            artifacts[:recording_rules].concat(slo_recording_rules(definition, sli, instance, slo))
            artifacts[:burn_rate_rules].concat(burn_rate_rules(definition, sli, instance, slo))
            artifacts[:missing_telemetry_rules] << missing_telemetry_rule(definition, sli, instance, slo)
            artifacts[:alert_rules] << burn_rate_alert(definition, sli, instance, slo)
            artifacts[:alertmanager_routes] << alertmanager_route(definition, slo)
            artifacts[:grafana_dashboards] << grafana_dashboard(definition, sli, instance, slo)
          end
        end

        artifacts.merge!(SloRulesEngine::PrometheusStack::ResourceRenderer.new.render(definition, artifacts))
        manifest(artifacts, definition: definition)
      end

      def validate(definition)
        super.tap do |result|
          definition.slis.each_with_index do |sli, sli_index|
            sli.instances.each_with_index do |instance, instance_index|
              instance.slos.each_with_index do |slo, slo_index|
                validate_threshold_slo(
                  result,
                  slo,
                  "slis[#{sli_index}].instances[#{instance_index}].slos[#{slo_index}]"
                )
              end
            end
          end
        end
      end

      private

      def supported_data_sources
        %w[prometheus openmetrics]
      end

      def required_route_sources
        %w[alertmanager]
      end

      def each_sli_instance(definition)
        definition.slis.each do |sli|
          sli.instances.each { |instance| yield sli, instance }
        end
      end

      def sli_recording_rule(definition, sli, instance)
        metric = sli.metric.binding_for(key)
        {
          kind: 'sli',
          metric: 'observations',
          record: record_name('sli', definition.service, sli.uid, instance.uid, 'observations'),
          labels: prometheus_sli_labels(definition, sli, instance),
          expr: observation_expression(metric, instance)
        }
      end

      def slo_recording_rules(definition, sli, instance, slo)
        labels = prometheus_labels(definition, sli, instance, slo)
        success_ratio_record = slo_record_name(definition, sli, instance, slo, 'success_ratio')
        [
          {
            kind: 'slo',
            metric: 'success_ratio',
            record: success_ratio_record,
            labels: labels,
            expr: success_ratio_expression(sli.metric.binding_for(key), instance, slo)
          },
          {
            kind: 'slo',
            metric: 'error_ratio',
            record: slo_record_name(definition, sli, instance, slo, 'error_ratio'),
            labels: labels,
            expr: "1 - #{success_ratio_record}"
          },
          {
            kind: 'slo',
            metric: 'objective_ratio',
            record: slo_record_name(definition, sli, instance, slo, 'objective_ratio'),
            labels: labels,
            expr: "vector(#{format_ratio(slo.objective)})"
          },
          {
            kind: 'slo',
            metric: 'error_budget_ratio',
            record: slo_record_name(definition, sli, instance, slo, 'error_budget_ratio'),
            labels: labels,
            expr: "vector(#{format_ratio(error_budget(slo))})"
          }
        ]
      end

      def burn_rate_rules(definition, sli, instance, slo)
        BurnRatePolicy.new.windows.map do |window|
          {
            record: slo_record_name(definition, sli, instance, slo, 'burn_rate', window[:range]),
            labels: prometheus_labels(definition, sli, instance, slo),
            range: window[:range],
            percent: window[:percent],
            threshold: window[:threshold],
            expr: "(1 - #{slo_record_name(definition, sli, instance, slo, 'success_ratio')}) / #{format_ratio(error_budget(slo))}"
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
          expr: "#{slo_record_name(definition, sli, instance, slo, 'burn_rate', fast_window[:range])} > #{fast_window[:threshold]}",
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
        elsif slo.success_threshold
          threshold_success_ratio_expression(metric, instance, slo.success_threshold)
        else
          "#{metric.metric}{#{labels}}"
        end
      end

      def observation_expression(metric, instance)
        return metric.query unless metric.query.to_s.empty?

        selector = metric.selector.merge(instance.selector)
        labels = selector.map { |key, value| "#{key}=#{value.inspect}" }.join(',')
        series = "#{metric.metric}{#{labels}}"
        return "sum(rate(#{series}[#{metric.range || '5m'}]))" if %w[counter histogram].include?(metric.type)
        return "avg(#{series})" if metric.type == 'gauge'

        series
      end

      def prometheus_sli_labels(definition, sli, instance)
        {
          service: definition.service,
          owner: definition.owner,
          sli: sli.uid,
          sli_instance: instance.uid
        }
      end

      def prometheus_labels(definition, sli, instance, slo)
        prometheus_sli_labels(definition, sli, instance).merge(
          slo: slo.uid,
          objective_ratio: slo.objective.to_s,
          calculation_basis: slo.calculation_basis
        )
      end

      def grafana_dashboard_path(definition, sli, instance, slo)
        "/d/slo/#{definition.service}?var-sli=#{sli.uid}&var-instance=#{instance.uid}&var-slo=#{slo.uid}"
      end

      def error_budget(slo)
        1.0 - slo.objective.to_f
      end

      def slo_record_name(definition, sli, instance, slo, *suffix)
        record_name('slo', definition.service, sli.uid, instance.uid, slo.uid, *suffix)
      end

      def record_name(*parts)
        parts.map { |part| part.to_s.gsub(/[^a-zA-Z0-9_]/, '_') }.join(':')
      end

      def format_ratio(value)
        format('%.12g', value.to_f)
      end

      def threshold_success_ratio_expression(metric, instance, threshold)
        expression = observation_expression(metric, instance)
        operator = threshold.fetch(:operator)
        value = format_ratio(Float(threshold.fetch(:value)))
        "avg_over_time(((#{expression}) #{operator} bool #{value})[#{metric.range || '5m'}:])"
      rescue ArgumentError, TypeError
        expression
      end

      def validate_threshold_slo(result, slo, path)
        return unless slo.success_threshold

        threshold = slo.success_threshold
        operators = %w[< <= > >= == !=]
        unless operators.include?(threshold[:operator])
          result.error("#{path}.success_threshold.operator", "must be one of: #{operators.join(', ')}")
        end
        begin
          Float(threshold[:value])
        rescue ArgumentError, TypeError
          result.error("#{path}.success_threshold.value", 'must be numeric for prometheus_stack')
        end
        return if slo.calculation_basis == 'time_slice'

        result.error("#{path}.calculation_basis", 'must be time_slice for prometheus_stack success_threshold SLOs')
      end
    end
  end
end
