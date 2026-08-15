# frozen_string_literal: true

module SloRulesEngine
  module Application
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
  end
end
