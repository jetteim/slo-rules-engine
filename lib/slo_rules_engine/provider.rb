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
    end
  end
end
