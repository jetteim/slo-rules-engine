# frozen_string_literal: true

module SloRulesEngine
  class ProviderRegistry
    def initialize
      @providers = {}
    end

    def register(provider)
      @providers[provider.key] = provider
    end

    def fetch(key)
      @providers.fetch(key.to_s) { raise KeyError, "unknown provider: #{key}" }
    end

    def list
      @providers.values
    end
  end

  class Provider
    attr_reader :key, :capabilities

    def initialize(key:, capabilities:)
      @key = key
      @capabilities = capabilities
    end

    def generate(_definition)
      raise NotImplementedError, "#{self.class} must implement #generate"
    end

    def validate(definition)
      result = ValidationResult.new
      definition.slis.each_with_index do |sli, sli_index|
        begin
          binding = sli.metric.binding_for(key)
          validate_binding(result, "slis[#{sli_index}].metric.provider_bindings.#{key}", binding)
        rescue KeyError
          result.error("slis[#{sli_index}].metric.provider_bindings.#{key}", "missing #{key} query binding")
        end
      end
      validate_required_routes(result, definition)
      result
    end

    def manifest(artifacts)
      GeneratedManifest.new(provider: key, capabilities: capabilities, artifacts: artifacts)
    end

    private

    def validate_binding(result, path, binding)
      result.error("#{path}.metric", 'is required') if binding.metric.to_s.empty?
      result.error("#{path}.data_source", 'is required') if binding.data_source.to_s.empty?
      result.error("#{path}.type", 'is required') if binding.type.to_s.empty?
      if !supported_data_sources.empty? && !supported_data_sources.include?(binding.data_source)
        result.error("#{path}.data_source", "unsupported data source #{binding.data_source.inspect} for provider #{key}")
      end
    end

    def validate_required_routes(result, definition)
      required_route_sources.each do |source|
        route_keys = definition.notification_routes.select { |route| route.source == source }.map(&:key)
        if route_keys.empty?
          result.error('notification_routes', "missing #{source} notification route source for provider #{key}")
          next
        end

        each_slo(definition) do |_sli, _instance, slo|
          effective_key = slo.alert_route_key || definition.service
          unless route_keys.include?(effective_key)
            result.error('notification_routes', "missing #{source} notification route #{effective_key.inspect} for provider #{key}")
          end
        end
      end
    end

    def each_slo(definition)
      definition.slis.each do |sli|
        sli.instances.each do |instance|
          instance.slos.each { |slo| yield sli, instance, slo }
        end
      end
    end

    def supported_data_sources
      []
    end

    def required_route_sources
      []
    end
  end
end
