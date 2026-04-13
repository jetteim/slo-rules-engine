# frozen_string_literal: true

module SloRulesEngine
  IntegrationManifest = Struct.new(
    :integration,
    :capabilities,
    :artifacts,
    keyword_init: true
  ) do
    def to_h
      {
        integration: integration,
        capabilities: capabilities,
        artifacts: artifacts
      }
    end
  end

  class IntegrationRegistry
    def initialize
      @integrations = {}
    end

    def register(integration)
      @integrations[integration.key] = integration
    end

    def fetch(key)
      @integrations.fetch(key.to_s) { raise KeyError, "unknown integration: #{key}" }
    end

    def list
      @integrations.values
    end
  end

  class Integration
    attr_reader :key, :capabilities

    def initialize(key:, capabilities:)
      @key = key
      @capabilities = capabilities
    end

    def generate(_definition)
      raise NotImplementedError, "#{self.class} must implement #generate"
    end

    def manifest(artifacts)
      IntegrationManifest.new(integration: key, capabilities: capabilities, artifacts: artifacts)
    end
  end
end
