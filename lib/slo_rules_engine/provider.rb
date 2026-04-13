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

    def manifest(artifacts)
      GeneratedManifest.new(provider: key, capabilities: capabilities, artifacts: artifacts)
    end
  end
end
