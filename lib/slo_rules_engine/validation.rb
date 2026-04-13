# frozen_string_literal: true

module SloRulesEngine
  ValidationMessage = Struct.new(:path, :message, :line_reference, keyword_init: true) do
    def to_h
      { path: path, message: message, line_reference: line_reference }.compact
    end
  end

  class ValidationResult
    attr_reader :errors, :warnings

    def initialize
      @errors = []
      @warnings = []
    end

    def error(path, message, line_reference: nil)
      errors << ValidationMessage.new(path: path, message: message, line_reference: line_reference)
    end

    def warning(path, message, line_reference: nil)
      warnings << ValidationMessage.new(path: path, message: message, line_reference: line_reference)
    end

    def valid?
      errors.empty?
    end

    def to_h
      {
        valid: valid?,
        errors: errors.map(&:to_h),
        warnings: warnings.map(&:to_h)
      }
    end
  end

  class CoreValidator
    NAME_PATTERN = /\A[a-z0-9][a-z0-9-]*\z/
    CALCULATION_BASES = %w[observations time_slice].freeze

    def validate(definition)
      result = ValidationResult.new
      validate_name(result, 'service', definition.service)
      validate_presence(result, 'owner', definition.owner)
      validate_environments(result, definition.environments)
      validate_routes(result, definition.notification_routes)
      validate_slis(result, definition.slis, route_keys(definition.notification_routes))
      result
    end

    private

    def validate_slis(result, slis, route_keys)
      result.error('slis', 'at least one SLI is required') if slis.empty?
      seen = {}
      slis.each_with_index do |sli, index|
        path = "slis[#{index}]"
        validate_name(result, "#{path}.uid", sli.uid, line_reference: line_reference(sli, :uid))
        result.error("#{path}.uid", 'SLI uid must be unique', line_reference: line_reference(sli, :uid)) if sli.uid && seen[sli.uid]
        seen[sli.uid] = true
        validate_presence(result, "#{path}.title", sli.title, line_reference: line_reference(sli, :title))
        validate_metric(result, "#{path}.metric", sli.metric)
        validate_instances(result, path, sli.instances, route_keys)
      end
    end

    def validate_instances(result, path, instances, route_keys)
      result.error("#{path}.instances", 'at least one SLI instance is required') if instances.empty?
      seen = {}
      instances.each_with_index do |instance, index|
        instance_path = "#{path}.instances[#{index}]"
        validate_name(result, "#{instance_path}.uid", instance.uid, line_reference: line_reference(instance, :uid))
        result.error("#{instance_path}.uid", 'SLI instance uid must be unique', line_reference: line_reference(instance, :uid)) if instance.uid && seen[instance.uid]
        seen[instance.uid] = true
        validate_hash(result, "#{instance_path}.selector", instance.selector, line_reference: line_reference(instance, :selector))
        validate_slos(result, instance_path, instance.slos, route_keys)
      end
    end

    def validate_slos(result, path, slos, route_keys)
      result.error("#{path}.slos", 'at least one SLO is required') if slos.empty?
      seen = {}
      slos.each_with_index do |slo, index|
        slo_path = "#{path}.slos[#{index}]"
        validate_name(result, "#{slo_path}.uid", slo.uid, line_reference: line_reference(slo, :uid))
        result.error("#{slo_path}.uid", 'SLO uid must be unique', line_reference: line_reference(slo, :uid)) if slo.uid && seen[slo.uid]
        seen[slo.uid] = true
        validate_objective(result, "#{slo_path}.objective", slo.objective, line_reference: line_reference(slo, :objective))
        unless CALCULATION_BASES.include?(slo.calculation_basis)
          result.error("#{slo_path}.calculation_basis", "must be one of: #{CALCULATION_BASES.join(', ')}", line_reference: line_reference(slo, :calculation_basis))
        end
        if empty?(slo.success_selector) && empty?(slo.success_threshold)
          result.error("#{slo_path}.success", 'success_selector or success_threshold is required')
        end
        validate_alert_route_key(result, "#{slo_path}.alert_route_key", slo, route_keys)
      end
    end

    def validate_metric(result, path, metric)
      if metric.nil?
        result.error(path, 'metric is required')
        return
      end
      validate_presence(result, "#{path}.name", metric.name, line_reference: line_reference(metric, :name))
      validate_presence(result, "#{path}.data_source", metric.data_source, line_reference: line_reference(metric, :data_source))
      validate_presence(result, "#{path}.type", metric.type, line_reference: line_reference(metric, :type))
      validate_hash(result, "#{path}.selector", metric.selector, line_reference: line_reference(metric, :selector))
      validate_hash(result, "#{path}.provider_bindings", metric.provider_bindings, line_reference: line_reference(metric, :provider_bindings))
      metric.provider_bindings.each do |provider, binding|
        validate_presence(result, "#{path}.provider_bindings.#{provider}.metric", binding.metric, line_reference: line_reference(binding, :metric))
        validate_presence(result, "#{path}.provider_bindings.#{provider}.data_source", binding.data_source, line_reference: line_reference(binding, :data_source))
        validate_presence(result, "#{path}.provider_bindings.#{provider}.type", binding.type, line_reference: line_reference(binding, :type))
        validate_hash(result, "#{path}.provider_bindings.#{provider}.selector", binding.selector, line_reference: line_reference(binding, :selector))
      end
    end

    def validate_routes(result, routes)
      routes.each_with_index do |route, index|
        path = "notification_routes[#{index}]"
        validate_name(result, "#{path}.key", route.key, line_reference: line_reference(route, :key))
        validate_presence(result, "#{path}.source", route.source, line_reference: line_reference(route, :source))
        validate_presence(result, "#{path}.provider", route.provider, line_reference: line_reference(route, :provider))
        validate_presence(result, "#{path}.target", route.target, line_reference: line_reference(route, :target))
      end
    end

    def validate_alert_route_key(result, path, slo, route_keys)
      return if empty?(slo.alert_route_key)
      return if route_keys.include?(slo.alert_route_key)

      result.error(path, "unknown notification route key #{slo.alert_route_key.inspect}", line_reference: line_reference(slo, :alert_route_key))
    end

    def validate_environments(result, environments)
      result.error('environments', 'at least one environment is required') if environments.empty?
      environments.each do |environment|
        validate_name(result, 'environments', environment, line_reference: line_reference_from_hash(environments, :environments))
      end
    end

    def validate_objective(result, path, objective, line_reference: nil)
      if objective.nil?
        result.error(path, 'objective is required', line_reference: line_reference)
      elsif objective <= 0 || objective >= 1
        result.error(path, 'objective must be a ratio greater than 0 and less than 1', line_reference: line_reference)
      end
    end

    def route_keys(routes)
      routes.map(&:key).compact.uniq
    end

    def validate_name(result, path, value, line_reference: nil)
      validate_presence(result, path, value, line_reference: line_reference)
      return if empty?(value)
      return if value.match?(NAME_PATTERN)

      result.error(path, 'must use lowercase letters, numbers, and dashes', line_reference: line_reference)
    end

    def validate_presence(result, path, value, line_reference: nil)
      result.error(path, 'is required', line_reference: line_reference) if empty?(value)
    end

    def validate_hash(result, path, value, line_reference: nil)
      result.error(path, 'must be a hash', line_reference: line_reference) unless value.is_a?(Hash)
    end

    def empty?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end

    def line_reference(object, field)
      object.respond_to?(:line_references) ? object.line_references[field] : nil
    end

    def line_reference_from_hash(_object, _field)
      nil
    end
  end
end
