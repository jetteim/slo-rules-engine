# frozen_string_literal: true

require 'json'
require 'optparse'

module SloRulesEngine
  module CLI
    module CatalogCommands
      def providers(argv)
        dispatch_registered_subcommand('providers', argv, 'usage: providers list')
      end

      def providers_list(_argv)
        providers = SloRulesEngine.default_provider_registry.list.map do |provider|
          {
            key: provider.key,
            capabilities: provider.capabilities,
            automation_mode: provider.automation_mode,
            state_actions: provider.state_actions
          }
        end
        puts JSON.pretty_generate(providers)
      end

      def integrations(argv)
        dispatch_registered_subcommand('integrations', argv, 'usage: integrations list')
      end

      def integrations_list(_argv)
        integrations = SloRulesEngine.default_integration_registry.list.map do |integration|
          { key: integration.key, capabilities: integration.capabilities }
        end
        puts JSON.pretty_generate(integrations)
      end

      def generate_routes(argv)
        integration_key = nil
        parser = OptionParser.new do |opts|
          opts.on('--integration=INTEGRATION', 'Integration key') { |value| integration_key = value }
        end
        parser.parse!(argv)
        abort_usage('missing --integration') unless integration_key

        integration = SloRulesEngine.default_integration_registry.fetch(integration_key)
        definitions = load_definitions(argv)
        manifests = definitions.map { |definition| integration.generate(definition).to_h.merge(service: definition.service) }
        puts JSON.pretty_generate(manifests)
      end
    end
  end
end
