# frozen_string_literal: true

module SloRulesEngine
  module Application
    Context = Struct.new(:provider_registry, :integration_registry, keyword_init: true)

    class CommandResult
      attr_reader :value, :side_effect, :findings, :artifacts

      def initialize(value:, side_effect: 'none', findings: [], artifacts: [])
        @value = value
        @side_effect = side_effect
        @findings = findings.freeze
        @artifacts = artifacts.freeze
        freeze
      end
    end

    class ListProviders
      def call(arguments, context:)
        require_empty_arguments!(arguments)
        providers = context.provider_registry.list.map do |provider|
          {
            key: provider.key,
            capabilities: provider.capabilities,
            automation_mode: provider.automation_mode,
            state_actions: provider.state_actions
          }
        end
        CommandResult.new(value: providers)
      end

      private

      def require_empty_arguments!(arguments)
        raise ArgumentError, 'providers.list does not accept arguments' unless arguments.empty?
      end
    end

    class ListIntegrations
      def call(arguments, context:)
        raise ArgumentError, 'integrations.list does not accept arguments' unless arguments.empty?

        integrations = context.integration_registry.list.map do |integration|
          { key: integration.key, capabilities: integration.capabilities }
        end
        CommandResult.new(value: integrations)
      end
    end

    class RecommendCalculationBasis
      def call(arguments, context:)
        recommendation = SloRulesEngine::RealityCheck::CalculationBasisAdvisor.new.recommend(
          observations_per_second: arguments.fetch('observations_per_second'),
          failed_observations_to_alert: arguments.fetch('failed_observations_to_alert')
        )
        CommandResult.new(value: recommendation.to_h)
      end
    end
  end
end
