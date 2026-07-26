# frozen_string_literal: true

module SloRulesEngine
  class ManifestSchemaError < StandardError
    attr_reader :result

    def initialize(result)
      @result = result
      super('manifest does not match provider schema')
    end
  end

  module ManifestSchemaValidator
    PROMETHEUS_METRIC_NAME = /\A[a-zA-Z_:][a-zA-Z0-9_:]*\z/

    module_function

    def validate(manifest)
      result = ValidationResult.new
      provider = fetch_value(manifest, :provider)
      validate_presence(result, 'provider', provider)
      validate_presence(result, 'service', fetch_value(manifest, :service))
      validate_review_provenance(result, fetch_value(manifest, :review_provenance)) if fetch_value(manifest, :review_provenance)
      artifacts = fetch_value(manifest, :artifacts)
      unless artifacts.is_a?(Hash)
        result.error('artifacts', 'must be a hash')
        return result
      end

      case provider.to_s
      when 'datadog'
        validate_datadog(result, artifacts)
      when 'prometheus_stack'
        validate_prometheus_stack(result, artifacts)
      when 'sloth'
        validate_sloth(result, artifacts)
      when ''
        nil
      else
        result.error('provider', "unsupported provider schema #{provider.inspect}")
      end

      result
    end

    def validate!(manifest)
      result = validate(manifest)
      raise ManifestSchemaError, result unless result.valid?

      manifest
    rescue ManifestSchemaError => error
      raise error
    rescue StandardError
      raise
    end

    def validate_datadog(result, artifacts)
      validate_collection(result, artifacts, :slos).each_with_index do |artifact, index|
        path = "artifacts.slos[#{index}]"
        validate_presence(result, "#{path}.name", fetch_value(artifact, :name))
        validate_presence(result, "#{path}.owner", fetch_value(artifact, :owner))
        validate_presence(result, "#{path}.sli", fetch_value(artifact, :sli))
        validate_presence(result, "#{path}.sli_instance", fetch_value(artifact, :sli_instance))
        validate_presence(result, "#{path}.slo", fetch_value(artifact, :slo))
        validate_objective_ratio(result, "#{path}.objective_ratio", fetch_value(artifact, :objective_ratio))
        validate_query_binding(result, "#{path}.query", fetch_value(artifact, :query), require_success_condition: true)
      end

      validate_collection(result, artifacts, :monitors).each_with_index do |artifact, index|
        validate_datadog_monitor(result, artifact, "artifacts.monitors[#{index}]")
      end

      validate_collection(result, artifacts, :telemetry_gap_monitors).each_with_index do |artifact, index|
        path = "artifacts.telemetry_gap_monitors[#{index}]"
        validate_datadog_monitor(result, artifact, path)
        validate_presence(result, "#{path}.classification", fetch_value(artifact, :classification))
        validate_query_binding(result, "#{path}.query", fetch_value(artifact, :query), require_success_condition: false)
      end

      validate_collection(result, artifacts, :dashboards).each_with_index do |artifact, index|
        path = "artifacts.dashboards[#{index}]"
        validate_presence(result, "#{path}.title", fetch_value(artifact, :title))
        validate_hash(result, "#{path}.variables", fetch_value(artifact, :variables))
        validate_presence(result, "#{path}.source", fetch_value(artifact, :source))
      end
    end

    def validate_prometheus_stack(result, artifacts)
      validate_collection(result, artifacts, :recording_rules).each_with_index do |rule, index|
        path = "artifacts.recording_rules[#{index}]"
        record = fetch_value(rule, :record)
        validate_presence(result, "#{path}.kind", fetch_value(rule, :kind))
        validate_presence(result, "#{path}.metric", fetch_value(rule, :metric))
        validate_presence(result, "#{path}.record", record)
        if !blank?(record) && !record.to_s.match?(PROMETHEUS_METRIC_NAME)
          result.error("#{path}.record", 'must be a valid Prometheus metric name')
        end
        validate_presence(result, "#{path}.expr", fetch_value(rule, :expr))
        validate_hash(result, "#{path}.labels", fetch_value(rule, :labels))
      end

      validate_collection(result, artifacts, :burn_rate_rules).each_with_index do |rule, index|
        path = "artifacts.burn_rate_rules[#{index}]"
        validate_presence(result, "#{path}.record", fetch_value(rule, :record))
        validate_presence(result, "#{path}.expr", fetch_value(rule, :expr))
        validate_presence(result, "#{path}.range", fetch_value(rule, :range))
        validate_numeric(result, "#{path}.threshold", fetch_value(rule, :threshold))
        validate_hash(result, "#{path}.labels", fetch_value(rule, :labels))
      end

      %i[missing_telemetry_rules alert_rules].each do |collection|
        validate_collection(result, artifacts, collection).each_with_index do |rule, index|
          path = "artifacts.#{collection}[#{index}]"
          validate_presence(result, "#{path}.alert", fetch_value(rule, :alert))
          validate_presence(result, "#{path}.expr", fetch_value(rule, :expr))
          validate_presence(result, "#{path}.for", fetch_value(rule, :for))
          validate_hash(result, "#{path}.labels", fetch_value(rule, :labels))
          validate_hash(result, "#{path}.annotations", fetch_value(rule, :annotations))
        end
      end

      validate_collection(result, artifacts, :alertmanager_routes).each_with_index do |route, index|
        path = "artifacts.alertmanager_routes[#{index}]"
        validate_hash(result, "#{path}.matchers", fetch_value(route, :matchers))
        validate_presence(result, "#{path}.receiver", fetch_value(route, :receiver))
      end

      validate_collection(result, artifacts, :grafana_dashboards).each_with_index do |dashboard, index|
        path = "artifacts.grafana_dashboards[#{index}]"
        validate_presence(result, "#{path}.title", fetch_value(dashboard, :title))
        validate_presence(result, "#{path}.path", fetch_value(dashboard, :path))
        validate_hash(result, "#{path}.variables", fetch_value(dashboard, :variables))
        validate_array(result, "#{path}.panels", fetch_value(dashboard, :panels))
      end

      validate_prometheus_rule_resources(result, artifacts)
      validate_grafana_dashboard_resources(result, artifacts)
      validate_alertmanager_route_bundles(result, artifacts)
    end

    def validate_prometheus_rule_resources(result, artifacts)
      resources = validate_collection(result, artifacts, :prometheus_rule_resources)
      result.error('artifacts.prometheus_rule_resources', 'must contain at least one resource') if resources.empty?
      resources.each_with_index do |resource, index|
        path = "artifacts.prometheus_rule_resources[#{index}]"
        validate_exact(result, "#{path}.apiVersion", fetch_value(resource, :apiVersion), 'monitoring.coreos.com/v1')
        validate_exact(result, "#{path}.kind", fetch_value(resource, :kind), 'PrometheusRule')
        validate_kubernetes_metadata(result, "#{path}.metadata", fetch_value(resource, :metadata))
        spec = fetch_value(resource, :spec)
        validate_hash(result, "#{path}.spec", spec)
        next unless spec.is_a?(Hash)

        groups = validate_collection(result, spec, :groups, path: "#{path}.spec.groups")
        result.error("#{path}.spec.groups", 'must contain at least one rule group') if groups.empty?
        groups.each_with_index do |group, group_index|
          group_path = "#{path}.spec.groups[#{group_index}]"
          validate_presence(result, "#{group_path}.name", fetch_value(group, :name))
          rules = validate_collection(result, group, :rules, path: "#{group_path}.rules")
          rules.each_with_index do |rule, rule_index|
            validate_prometheus_rule(result, rule, "#{group_path}.rules[#{rule_index}]")
          end
        end
      end
    end

    def validate_prometheus_rule(result, rule, path)
      validate_hash(result, path, rule)
      return unless rule.is_a?(Hash)

      record = fetch_value(rule, :record)
      alert = fetch_value(rule, :alert)
      if blank?(record) == blank?(alert)
        result.error(path, 'must define exactly one of record or alert')
      elsif !blank?(record) && !record.to_s.match?(PROMETHEUS_METRIC_NAME)
        result.error("#{path}.record", 'must be a valid Prometheus metric name')
      end
      validate_presence(result, "#{path}.expr", fetch_value(rule, :expr))
      validate_hash(result, "#{path}.labels", fetch_value(rule, :labels))
      return if blank?(alert)

      validate_presence(result, "#{path}.for", fetch_value(rule, :for))
      validate_hash(result, "#{path}.annotations", fetch_value(rule, :annotations))
    end

    def validate_grafana_dashboard_resources(result, artifacts)
      resources = validate_collection(result, artifacts, :grafana_dashboard_resources)
      result.error('artifacts.grafana_dashboard_resources', 'must contain at least one resource') if resources.empty?
      resources.each_with_index do |resource, index|
        path = "artifacts.grafana_dashboard_resources[#{index}]"
        validate_exact(result, "#{path}.apiVersion", fetch_value(resource, :apiVersion), 'v1')
        validate_exact(result, "#{path}.kind", fetch_value(resource, :kind), 'ConfigMap')
        validate_kubernetes_metadata(result, "#{path}.metadata", fetch_value(resource, :metadata))
        data = fetch_value(resource, :data)
        validate_hash(result, "#{path}.data", data)
        next unless data.is_a?(Hash)

        result.error("#{path}.data", 'must contain at least one Grafana dashboard') if data.empty?
        data.each do |filename, dashboard_json|
          dashboard_path = "#{path}.data.#{filename}"
          begin
            dashboard = JSON.parse(dashboard_json)
            validate_presence(result, "#{dashboard_path}.uid", dashboard['uid'])
            validate_presence(result, "#{dashboard_path}.title", dashboard['title'])
            validate_numeric(result, "#{dashboard_path}.schemaVersion", dashboard['schemaVersion'])
            validate_array(result, "#{dashboard_path}.panels", dashboard['panels'])
          rescue JSON::ParserError, TypeError
            result.error(dashboard_path, 'must be valid Grafana dashboard JSON')
          end
        end
      end
    end

    def validate_alertmanager_route_bundles(result, artifacts)
      bundles = validate_collection(result, artifacts, :alertmanager_route_bundles)
      result.error('artifacts.alertmanager_route_bundles', 'must contain at least one route intent') if bundles.empty?
      bundles.each_with_index do |bundle, index|
        path = "artifacts.alertmanager_route_bundles[#{index}]"
        validate_exact(
          result,
          "#{path}.version",
          fetch_value(bundle, :version),
          'slo-rules-engine/alertmanager-route-intent/v1'
        )
        validate_exact(result, "#{path}.kind", fetch_value(bundle, :kind), 'AlertmanagerRouteIntent')
        validate_presence(result, "#{path}.service", fetch_value(bundle, :service))
        validate_kubernetes_metadata(result, "#{path}.metadata", fetch_value(bundle, :metadata))
        receiver = fetch_value(bundle, :receiver_contract)
        validate_hash(result, "#{path}.receiver_contract", receiver)
        if receiver.is_a?(Hash)
          validate_presence(result, "#{path}.receiver_contract.name", fetch_value(receiver, :name))
          validate_exact(result, "#{path}.receiver_contract.type", fetch_value(receiver, :type), 'webhook')
          validate_presence(result, "#{path}.receiver_contract.endpoint_path", fetch_value(receiver, :endpoint_path))
          validate_exact(
            result,
            "#{path}.receiver_contract.configuration_required",
            fetch_value(receiver, :configuration_required),
            true
          )
        end
        validate_collection(result, bundle, :routes, path: "#{path}.routes").each_with_index do |route, route_index|
          route_path = "#{path}.routes[#{route_index}]"
          validate_hash(result, "#{route_path}.matchers", fetch_value(route, :matchers))
          validate_presence(result, "#{route_path}.receiver", fetch_value(route, :receiver))
          validate_presence(result, "#{route_path}.webhook_path", fetch_value(route, :webhook_path))
        end
      end
    end

    def validate_kubernetes_metadata(result, path, metadata)
      validate_hash(result, path, metadata)
      return unless metadata.is_a?(Hash)

      validate_presence(result, "#{path}.name", fetch_value(metadata, :name))
      validate_hash(result, "#{path}.labels", fetch_value(metadata, :labels))
      validate_hash(result, "#{path}.annotations", fetch_value(metadata, :annotations))
    end

    def validate_sloth(result, artifacts)
      validate_collection(result, artifacts, :sloth_specs).each_with_index do |spec, index|
        path = "artifacts.sloth_specs[#{index}]"
        validate_presence(result, "#{path}.version", fetch_value(spec, :version))
        validate_presence(result, "#{path}.service", fetch_value(spec, :service))
        validate_hash(result, "#{path}.labels", fetch_value(spec, :labels))

        validate_collection(result, spec, :slos, path: "#{path}.slos").each_with_index do |slo, slo_index|
          slo_path = "#{path}.slos[#{slo_index}]"
          validate_presence(result, "#{slo_path}.name", fetch_value(slo, :name))
          validate_numeric(result, "#{slo_path}.objective", fetch_value(slo, :objective))
          validate_presence(result, "#{slo_path}.description", fetch_value(slo, :description))
          sli = fetch_value(slo, :sli)
          validate_hash(result, "#{slo_path}.sli", sli)
          if sli.is_a?(Hash)
            events = fetch_value(sli, :events)
            validate_hash(result, "#{slo_path}.sli.events", events)
            if events.is_a?(Hash)
              validate_presence(result, "#{slo_path}.sli.events.total_query", fetch_value(events, :total_query))
              validate_presence(result, "#{slo_path}.sli.events.error_query", fetch_value(events, :error_query))
            end
          end

          alerting = fetch_value(slo, :alerting)
          validate_hash(result, "#{slo_path}.alerting", alerting)
          next unless alerting.is_a?(Hash)

          validate_presence(result, "#{slo_path}.alerting.name", fetch_value(alerting, :name))
          validate_hash(result, "#{slo_path}.alerting.labels", fetch_value(alerting, :labels))
          validate_hash(result, "#{slo_path}.alerting.page_alert", fetch_value(alerting, :page_alert))
          validate_hash(result, "#{slo_path}.alerting.ticket_alert", fetch_value(alerting, :ticket_alert))
        end
      end
    end

    def validate_datadog_monitor(result, artifact, path)
      validate_presence(result, "#{path}.name", fetch_value(artifact, :name))
      validate_presence(result, "#{path}.type", fetch_value(artifact, :type))
      validate_presence(result, "#{path}.route_key", fetch_value(artifact, :route_key))
      validate_hash(result, "#{path}.message_context", fetch_value(artifact, :message_context))

      case fetch_value(artifact, :type)
      when 'burn_rate'
        windows = validate_collection(result, artifact, :burn_rate_windows, path: "#{path}.burn_rate_windows")
        windows.each_with_index do |window, index|
          window_path = "#{path}.burn_rate_windows[#{index}]"
          validate_presence(result, "#{window_path}.range", fetch_value(window, :range))
          validate_numeric(result, "#{window_path}.threshold", fetch_value(window, :threshold))
        end
      when 'missing_telemetry'
        nil
      else
        result.error("#{path}.type", "unsupported datadog monitor type #{fetch_value(artifact, :type).inspect}")
      end
    end

    def validate_review_provenance(result, provenance)
      validate_hash(result, 'review_provenance', provenance)
      return unless provenance.is_a?(Hash)

      validate_presence(result, 'review_provenance.label', fetch_value(provenance, :label))
      validate_presence(result, 'review_provenance.provider', fetch_value(provenance, :provider))
      validate_array(result, 'review_provenance.accepted_candidate_uids', fetch_value(provenance, :accepted_candidate_uids))
      validate_array(result, 'review_provenance.rejected_candidate_uids', fetch_value(provenance, :rejected_candidate_uids)) if fetch_value(provenance, :rejected_candidate_uids)
      validate_array(result, 'review_provenance.notes', fetch_value(provenance, :notes)) if fetch_value(provenance, :notes)
    end

    def validate_query_binding(result, path, query, require_success_condition:)
      validate_hash(result, path, query)
      return unless query.is_a?(Hash)

      validate_presence(result, "#{path}.metric", fetch_value(query, :metric))
      validate_presence(result, "#{path}.data_source", fetch_value(query, :data_source))
      validate_presence(result, "#{path}.type", fetch_value(query, :type))
      validate_hash(result, "#{path}.selector", fetch_value(query, :selector))
      return unless require_success_condition

      success_selector = fetch_value(query, :success_selector)
      success_threshold = fetch_value(query, :success_threshold)
      if success_selector.nil? && success_threshold.nil?
        result.error(path, 'success_selector or success_threshold is required')
        return
      end

      if success_selector
        validate_hash(result, "#{path}.success_selector", success_selector)
        result.error("#{path}.success_selector", 'is required') if success_selector.is_a?(Hash) && success_selector.empty?
      end

      return unless success_threshold

      validate_hash(result, "#{path}.success_threshold", success_threshold)
      return unless success_threshold.is_a?(Hash)

      validate_presence(result, "#{path}.success_threshold.operator", fetch_value(success_threshold, :operator))
      validate_presence(result, "#{path}.success_threshold.value", fetch_value(success_threshold, :value))
      query_expression = fetch_value(query, :query)
      return unless blank?(query_expression)

      inferable_types = %w[counter distribution gauge]
      type = fetch_value(query, :type).to_s
      result.error("#{path}.query", "is required for success_threshold when type is not one of #{inferable_types.inspect}") unless inferable_types.include?(type)
    end

    def validate_collection(result, container, key, path: nil)
      collection_path = path || "artifacts.#{key}"
      value = fetch_value(container, key)
      unless value.is_a?(Array)
        result.error(collection_path, 'must be an array')
        return []
      end

      value
    end

    def validate_presence(result, path, value)
      result.error(path, 'is required') if blank?(value)
    end

    def validate_hash(result, path, value)
      result.error(path, 'must be a hash') unless value.is_a?(Hash)
    end

    def validate_array(result, path, value)
      result.error(path, 'must be an array') unless value.is_a?(Array)
    end

    def validate_numeric(result, path, value)
      result.error(path, 'must be numeric') unless value.is_a?(Numeric)
    end

    def validate_exact(result, path, value, expected)
      result.error(path, "must equal #{expected.inspect}") unless value == expected
    end

    def validate_objective_ratio(result, path, value)
      validate_numeric(result, path, value)
      return unless value.is_a?(Numeric)

      result.error(path, 'must be a ratio greater than 0 and less than 1') unless value > 0 && value < 1
    end

    def blank?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end

    def fetch_value(container, key)
      return container.public_send(key) if container.respond_to?(key)
      return nil unless container.respond_to?(:fetch)

      container.fetch(key) { container.fetch(key.to_s, nil) }
    end
  end
end
