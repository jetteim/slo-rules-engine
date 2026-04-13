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
          artifacts[:dashboards] << dashboard(definition, sli, instance, slo)
        end

        manifest(artifacts)
      end

      private

      def each_slo(definition)
        definition.slis.each do |sli|
          sli.instances.each do |instance|
            instance.slos.each { |slo| yield sli, instance, slo }
          end
        end
      end

      def datadog_query(metric, instance, slo)
        selector = metric.selector.merge(instance.selector)
        {
          data_source: metric.data_source,
          metric: metric.name,
          type: metric.type,
          selector: selector,
          success_selector: slo.success_selector,
          success_threshold: slo.success_threshold
        }
      end

      def contextual_monitor(definition, sli, instance, slo)
        {
          name: "SLO burn rate: #{definition.service}/#{sli.uid}/#{instance.uid}/#{slo.uid}",
          type: 'burn_rate',
          route_key: slo.alert_route_key || definition.service,
          message_context: alert_context(definition, sli, instance, slo)
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
