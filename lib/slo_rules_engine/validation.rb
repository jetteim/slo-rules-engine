# frozen_string_literal: true

module SloRulesEngine
  ValidationMessage = Struct.new(:path, :message, keyword_init: true) do
    def to_h
      { path: path, message: message }
    end
  end

  class ValidationResult
    attr_reader :errors, :warnings

    def initialize
      @errors = []
      @warnings = []
    end

    def error(path, message)
      errors << ValidationMessage.new(path: path, message: message)
    end

    def warning(path, message)
      warnings << ValidationMessage.new(path: path, message: message)
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
      validate_slis(result, definition.slis)
      result
    end

    private

    def validate_slis(result, slis)
      result.error('slis', 'at least one SLI is required') if slis.empty?
      seen = {}
      slis.each_with_index do |sli, index|
        path = "slis[#{index}]"
        validate_name(result, "#{path}.uid", sli.uid)
        result.error("#{path}.uid", 'SLI uid must be unique') if sli.uid && seen[sli.uid]
        seen[sli.uid] = true
        validate_presence(result, "#{path}.title", sli.title)
        validate_metric(result, "#{path}.metric", sli.metric)
        validate_instances(result, path, sli.instances)
      end
    end

    def validate_instances(result, path, instances)
      result.error("#{path}.instances", 'at least one SLI instance is required') if instances.empty?
      seen = {}
      instances.each_with_index do |instance, index|
        instance_path = "#{path}.instances[#{index}]"
        validate_name(result, "#{instance_path}.uid", instance.uid)
        result.error("#{instance_path}.uid", 'SLI instance uid must be unique') if instance.uid && seen[instance.uid]
        seen[instance.uid] = true
        validate_hash(result, "#{instance_path}.selector", instance.selector)
        validate_slos(result, instance_path, instance.slos)
      end
    end

    def validate_slos(result, path, slos)
      result.error("#{path}.slos", 'at least one SLO is required') if slos.empty?
      seen = {}
      slos.each_with_index do |slo, index|
        slo_path = "#{path}.slos[#{index}]"
        validate_name(result, "#{slo_path}.uid", slo.uid)
        result.error("#{slo_path}.uid", 'SLO uid must be unique') if slo.uid && seen[slo.uid]
        seen[slo.uid] = true
        validate_objective(result, "#{slo_path}.objective", slo.objective)
        unless CALCULATION_BASES.include?(slo.calculation_basis)
          result.error("#{slo_path}.calculation_basis", "must be one of: #{CALCULATION_BASES.join(', ')}")
        end
        if empty?(slo.success_selector) && empty?(slo.success_threshold)
          result.error("#{slo_path}.success", 'success_selector or success_threshold is required')
        end
      end
    end

    def validate_metric(result, path, metric)
      if metric.nil?
        result.error(path, 'metric is required')
        return
      end
      validate_presence(result, "#{path}.name", metric.name)
      validate_presence(result, "#{path}.data_source", metric.data_source)
      validate_presence(result, "#{path}.type", metric.type)
      validate_hash(result, "#{path}.selector", metric.selector)
      validate_hash(result, "#{path}.provider_bindings", metric.provider_bindings)
      metric.provider_bindings.each do |provider, binding|
        validate_presence(result, "#{path}.provider_bindings.#{provider}.metric", binding.metric)
        validate_presence(result, "#{path}.provider_bindings.#{provider}.data_source", binding.data_source)
        validate_presence(result, "#{path}.provider_bindings.#{provider}.type", binding.type)
        validate_hash(result, "#{path}.provider_bindings.#{provider}.selector", binding.selector)
      end
    end

    def validate_routes(result, routes)
      routes.each_with_index do |route, index|
        path = "notification_routes[#{index}]"
        validate_name(result, "#{path}.key", route.key)
        validate_presence(result, "#{path}.source", route.source)
        validate_presence(result, "#{path}.provider", route.provider)
        validate_presence(result, "#{path}.target", route.target)
      end
    end

    def validate_environments(result, environments)
      result.error('environments', 'at least one environment is required') if environments.empty?
      environments.each do |environment|
        validate_name(result, 'environments', environment)
      end
    end

    def validate_objective(result, path, objective)
      if objective.nil?
        result.error(path, 'objective is required')
      elsif objective <= 0 || objective >= 1
        result.error(path, 'objective must be a ratio greater than 0 and less than 1')
      end
    end

    def validate_name(result, path, value)
      validate_presence(result, path, value)
      return if empty?(value)
      return if value.match?(NAME_PATTERN)

      result.error(path, 'must use lowercase letters, numbers, and dashes')
    end

    def validate_presence(result, path, value)
      result.error(path, 'is required') if empty?(value)
    end

    def validate_hash(result, path, value)
      result.error(path, 'must be a hash') unless value.is_a?(Hash)
    end

    def empty?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end
  end
end
