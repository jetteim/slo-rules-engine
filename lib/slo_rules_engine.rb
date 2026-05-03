# frozen_string_literal: true

require 'json'
require 'yaml'

require_relative 'slo_rules_engine/model'
require_relative 'slo_rules_engine/validation'
require_relative 'slo_rules_engine/burn_rate_policy'
require_relative 'slo_rules_engine/dsl'
require_relative 'slo_rules_engine/provider'
require_relative 'slo_rules_engine/apply'
require_relative 'slo_rules_engine/manifest_schema'
require_relative 'slo_rules_engine/datadog/payload_canonicalizer'
require_relative 'slo_rules_engine/datadog/client'
require_relative 'slo_rules_engine/appliers/manifest_bundle'
require_relative 'slo_rules_engine/appliers/datadog'
require_relative 'slo_rules_engine/integration'
require_relative 'slo_rules_engine/migration_report'
require_relative 'slo_rules_engine/providers/datadog'
require_relative 'slo_rules_engine/providers/prometheus_stack'
require_relative 'slo_rules_engine/providers/sloth'
require_relative 'slo_rules_engine/integrations/notification_router'
require_relative 'slo_rules_engine/reality_check'
require_relative 'slo_rules_engine/telemetry_lookup'
require_relative 'slo_rules_engine/telemetry_lookup/datadog'
require_relative 'slo_rules_engine/telemetry_lookup/prometheus'
require_relative 'slo_rules_engine/onboarding/candidate_generator'
require_relative 'slo_rules_engine/onboarding/definition_draft_generator'
require_relative 'slo_rules_engine/reliability_model'

module SloRulesEngine
  class << self
    def definitions
      @definitions ||= []
    end

    def clear_definitions
      definitions.clear
    end

    def register_definition(definition)
      definitions << definition
      definition
    end

    def default_provider_registry
      ProviderRegistry.new.tap do |registry|
        registry.register(Providers::Datadog.new)
        registry.register(Providers::PrometheusStack.new)
        registry.register(Providers::Sloth.new)
      end
    end

    def default_integration_registry
      IntegrationRegistry.new.tap do |registry|
        registry.register(Integrations::NotificationRouter.new)
      end
    end
  end
end
