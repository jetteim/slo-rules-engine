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
    module_function

    def validate(manifest)
      result = ValidationResult.new
      provider = fetch_value(manifest, :provider)
      validate_presence(result, 'provider', provider)
      validate_presence(result, 'service', fetch_value(manifest, :service))
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
        validate_query_binding(result, "#{path}.query", fetch_value(artifact, :query), require_success_selector: true)
      end

      validate_collection(result, artifacts, :monitors).each_with_index do |artifact, index|
        validate_datadog_monitor(result, artifact, "artifacts.monitors[#{index}]")
      end

      validate_collection(result, artifacts, :telemetry_gap_monitors).each_with_index do |artifact, index|
        path = "artifacts.telemetry_gap_monitors[#{index}]"
        validate_datadog_monitor(result, artifact, path)
        validate_presence(result, "#{path}.classification", fetch_value(artifact, :classification))
        validate_query_binding(result, "#{path}.query", fetch_value(artifact, :query), require_success_selector: false)
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
        validate_presence(result, "#{path}.record", fetch_value(rule, :record))
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

    def validate_query_binding(result, path, query, require_success_selector:)
      validate_hash(result, path, query)
      return unless query.is_a?(Hash)

      validate_presence(result, "#{path}.metric", fetch_value(query, :metric))
      validate_presence(result, "#{path}.data_source", fetch_value(query, :data_source))
      validate_presence(result, "#{path}.type", fetch_value(query, :type))
      validate_hash(result, "#{path}.selector", fetch_value(query, :selector))
      validate_presence(result, "#{path}.query", fetch_value(query, :query))
      return unless require_success_selector

      validate_hash(result, "#{path}.success_selector", fetch_value(query, :success_selector))
      selector = fetch_value(query, :success_selector)
      result.error("#{path}.success_selector", 'is required') if selector.is_a?(Hash) && selector.empty?
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
