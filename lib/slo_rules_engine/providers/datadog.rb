# frozen_string_literal: true

module SloRulesEngine
  module Providers
    class Datadog < Provider
      def initialize
        super(
          key: 'datadog',
          capabilities: %w[
            sli_query_binding
            slo_evaluation
            burn_rate_alerting
            missing_telemetry_detection
            contextual_alerts
            notification_router_integration
            parameterized_dashboards
            reality_check
          ]
        )
      end

      def generate(definition)
        artifacts = {
          slos: [],
          monitors: [],
          telemetry_gap_monitors: [],
          dashboards: []
        }

        each_slo(definition) do |sli, instance, slo|
          artifacts[:slos] << {
            name: "#{definition.service} #{sli.uid} #{instance.uid} #{slo.uid}",
            service: definition.service,
            owner: definition.owner,
            sli: sli.uid,
            sli_instance: instance.uid,
            slo: slo.uid,
            objective_ratio: slo.objective,
            calculation_basis: slo.calculation_basis,
            query: datadog_query(sli.metric, instance, slo)
          }
          artifacts[:monitors] << contextual_monitor(definition, sli, instance, slo)
          artifacts[:telemetry_gap_monitors] << telemetry_gap_monitor(definition, sli, instance, slo)
          artifacts[:dashboards] << dashboard(definition, sli, instance, slo)
        end

        manifest(artifacts)
      end

      private

      def supported_data_sources
        %w[datadog]
      end

      def required_route_sources
        %w[datadog]
      end

      def each_slo(definition)
        definition.slis.each do |sli|
          sli.instances.each do |instance|
            instance.slos.each { |slo| yield sli, instance, slo }
          end
        end
      end

      def datadog_query(metric, instance, slo)
        binding = metric.binding_for(key)
        selector = binding.selector.merge(instance.selector)
        {
          data_source: binding.data_source,
          metric: binding.metric,
          type: binding.type,
          selector: selector,
          query: binding.query,
          success_selector: slo.success_selector,
          success_threshold: slo.success_threshold
        }
      end

      def contextual_monitor(definition, sli, instance, slo)
        {
          name: "SLO burn rate: #{definition.service}/#{sli.uid}/#{instance.uid}/#{slo.uid}",
          type: 'burn_rate',
          route_key: slo.alert_route_key || definition.service,
          burn_rate_windows: BurnRatePolicy.new.windows,
          message_context: alert_context(definition, sli, instance, slo)
        }
      end

      def telemetry_gap_monitor(definition, sli, instance, slo)
        {
          name: "SLO telemetry gap: #{definition.service}/#{sli.uid}/#{instance.uid}",
          type: 'missing_telemetry',
          classification: 'notification',
          route_key: slo.alert_route_key || definition.service,
          query: datadog_query(sli.metric, instance, slo),
          message_context: alert_context(definition, sli, instance, slo).merge(
            impact: 'SLO decision support is incomplete until telemetry resumes.'
          )
        }
      end

      def dashboard(definition, sli, instance, slo)
        {
          title: "#{definition.service} SLO decision dashboard",
          variables: {
            'service' => definition.service,
            'sli' => sli.uid,
            'sli_instance' => instance.uid,
            'slo' => slo.uid
          }.merge(instance.dashboard_variables),
          source: slo.dashboard_path || 'generated'
        }
      end

      def alert_context(definition, sli, instance, slo)
        {
          service: definition.service,
          owner: definition.owner,
          sli: sli.uid,
          sli_instance: instance.uid,
          slo: slo.uid,
          objective_ratio: slo.objective,
          playbook_url: instance.playbook_url,
          dashboard_path: slo.dashboard_path
        }
      end
    end
  end
end
