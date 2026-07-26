# frozen_string_literal: true

module SloRulesEngine
  module PrometheusStack
    class ResourceRenderer
      def render(definition, artifacts)
        {
          prometheus_rule_resources: [prometheus_rule(definition, artifacts)],
          grafana_dashboard_resources: [grafana_dashboard_config_map(definition, artifacts)],
          alertmanager_route_bundles: [alertmanager_route_bundle(definition, artifacts)]
        }
      end

      private

      def prometheus_rule(definition, artifacts)
        recording_rules = artifacts.fetch(:recording_rules)
        {
          apiVersion: 'monitoring.coreos.com/v1',
          kind: 'PrometheusRule',
          metadata: metadata(definition, 'slo-rules'),
          spec: {
            groups: [
              rule_group(
                "#{definition.service}.sli-recording",
                recording_rules.select { |rule| rule[:kind] == 'sli' }.map { |rule| recording_rule(rule) }
              ),
              rule_group(
                "#{definition.service}.slo-recording",
                recording_rules.select { |rule| rule[:kind] == 'slo' }.map { |rule| recording_rule(rule) }
              ),
              rule_group(
                "#{definition.service}.slo-burn-rate",
                artifacts.fetch(:burn_rate_rules).map { |rule| recording_rule(rule) }
              ),
              rule_group(
                "#{definition.service}.slo-alerts",
                (artifacts.fetch(:missing_telemetry_rules) + artifacts.fetch(:alert_rules)).map do |rule|
                  alert_rule(rule)
                end
              )
            ]
          }
        }
      end

      def grafana_dashboard_config_map(definition, artifacts)
        {
          apiVersion: 'v1',
          kind: 'ConfigMap',
          metadata: metadata(definition, 'slo-dashboards').tap do |value|
            value.fetch(:labels)['grafana_dashboard'] = '1'
          end,
          data: {
            "#{definition.service}-slo.json" => JSON.pretty_generate(grafana_dashboard(definition, artifacts))
          }
        }
      end

      def grafana_dashboard(definition, artifacts)
        {
          uid: kubernetes_name(definition.service, 'slo'),
          title: "#{definition.service} SLO decision dashboard",
          tags: ['slo', 'slo-rules-engine', "service:#{definition.service}"],
          timezone: 'browser',
          editable: false,
          graphTooltip: 1,
          schemaVersion: 39,
          version: 1,
          refresh: '1m',
          time: {
            from: 'now-30d',
            to: 'now'
          },
          templating: {
            list: [
              {
                name: 'datasource',
                label: 'Prometheus datasource',
                type: 'datasource',
                query: 'prometheus',
                refresh: 1
              }
            ]
          },
          panels: grafana_panels(artifacts)
        }
      end

      def grafana_panels(artifacts)
        artifacts.fetch(:grafana_dashboards).flat_map.with_index do |dashboard, slo_index|
          variables = dashboard.fetch(:variables)
          rules = rules_for_dashboard(artifacts, variables)
          panel_specs = [
            ['Success Ratio', [rules.fetch('success_ratio')], 'percentunit'],
            ['Error Ratio', [rules.fetch('error_ratio')], 'percentunit'],
            ['Error Budget Ratio', [rules.fetch('error_budget_ratio')], 'percentunit'],
            ['Burn Rate', rules.fetch('burn_rate'), 'short'],
            ['SLI Observations', [rules.fetch('observations')], 'short']
          ]

          panel_specs.each_with_index.map do |(title, records, unit), panel_index|
            panel_id = (slo_index * panel_specs.length) + panel_index + 1
            grafana_panel(
              panel_id,
              "#{variables.fetch('slo')} - #{title}",
              records,
              unit
            )
          end
        end
      end

      def rules_for_dashboard(artifacts, variables)
        labels = {
          service: variables.fetch('service'),
          sli: variables.fetch('sli'),
          sli_instance: variables.fetch('sli_instance'),
          slo: variables.fetch('slo')
        }
        recording = artifacts.fetch(:recording_rules)
        {
          'success_ratio' => record_with_metric(recording, labels, 'success_ratio'),
          'error_ratio' => record_with_metric(recording, labels, 'error_ratio'),
          'error_budget_ratio' => record_with_metric(recording, labels, 'error_budget_ratio'),
          'burn_rate' => records_with_labels(artifacts.fetch(:burn_rate_rules), labels),
          'observations' => record_with_metric(recording, labels.reject { |key, _value| key == :slo }, 'observations')
        }
      end

      def record_with_metric(rules, labels, metric)
        rule = rules.find do |candidate|
          candidate[:metric] == metric && labels_match?(candidate.fetch(:labels), labels)
        end
        rule ? rule.fetch(:record) : raise(KeyError, "missing #{metric} recording rule for #{labels.inspect}")
      end

      def records_with_labels(rules, labels)
        matches = rules.select { |rule| labels_match?(rule.fetch(:labels), labels) }.map { |rule| rule.fetch(:record) }
        raise KeyError, "missing burn-rate recording rules for #{labels.inspect}" if matches.empty?

        matches
      end

      def labels_match?(candidate, expected)
        expected.all? { |key, value| candidate[key].to_s == value.to_s }
      end

      def grafana_panel(id, title, records, unit)
        row = (id - 1) / 2
        column = (id - 1) % 2
        {
          id: id,
          title: title,
          type: 'timeseries',
          datasource: {
            type: 'prometheus',
            uid: '${datasource}'
          },
          gridPos: {
            h: 8,
            w: 12,
            x: column * 12,
            y: row * 8
          },
          fieldConfig: {
            defaults: {
              unit: unit
            },
            overrides: []
          },
          options: {
            legend: {
              displayMode: 'list',
              placement: 'bottom'
            },
            tooltip: {
              mode: 'multi',
              sort: 'desc'
            }
          },
          targets: records.each_with_index.map do |record, index|
            {
              refId: (65 + index).chr,
              expr: record,
              legendFormat: record.split(':').last
            }
          end
        }
      end

      def alertmanager_route_bundle(definition, artifacts)
        routes = artifacts.fetch(:alertmanager_routes).map do |route|
          route_key = route.fetch(:matchers).fetch(:route_key)
          {
            matchers: route.fetch(:matchers),
            receiver: route.fetch(:receiver),
            webhook_path: "/api/alertmanager/#{route_key}"
          }
        end.uniq

        {
          version: 'slo-rules-engine/alertmanager-route-intent/v1',
          kind: 'AlertmanagerRouteIntent',
          service: definition.service,
          metadata: metadata(definition, 'alertmanager-routes'),
          receiver_contract: {
            name: 'notification-router',
            type: 'webhook',
            endpoint_path: '/api/alertmanager/:route_key',
            configuration_required: true
          },
          routes: routes
        }.tap do |bundle|
          bundle[:review_provenance] = definition.review_provenance.to_h if definition.review_provenance
        end
      end

      def metadata(definition, suffix)
        annotations = {
          'slo-rules-engine.io/source-ref' => "service/#{definition.service}"
        }
        if definition.review_provenance
          annotations['slo-rules-engine.io/review-label'] = definition.review_provenance.label
        end
        {
          name: kubernetes_name(definition.service, suffix),
          labels: {
            'app.kubernetes.io/managed-by' => 'slo-rules-engine',
            'slo-rules-engine.io/service' => definition.service
          },
          annotations: annotations
        }
      end

      def rule_group(name, rules)
        {
          name: name,
          rules: rules
        }
      end

      def recording_rule(rule)
        {
          record: rule.fetch(:record),
          expr: rule.fetch(:expr),
          labels: stringify_values(rule.fetch(:labels))
        }
      end

      def alert_rule(rule)
        {
          alert: rule.fetch(:alert),
          expr: rule.fetch(:expr),
          for: rule.fetch(:for),
          labels: stringify_values(rule.fetch(:labels)),
          annotations: stringify_values(rule.fetch(:annotations).compact)
        }
      end

      def stringify_values(values)
        values.to_h { |key, value| [key, value.to_s] }
      end

      def kubernetes_name(*parts)
        parts.join('-').downcase.gsub(/[^a-z0-9.-]+/, '-').gsub(/\A[-.]+|[-.]+\z/, '')[0, 63]
      end
    end
  end
end
