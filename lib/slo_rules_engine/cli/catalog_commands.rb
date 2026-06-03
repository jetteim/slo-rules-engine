# frozen_string_literal: true

require 'json'
require 'optparse'

module SloRulesEngine
  module CLI
    module CatalogCommands
      def providers(argv)
        subcommand = argv.shift
        abort_usage('usage: providers list') unless subcommand == 'list'

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
        subcommand = argv.shift
        abort_usage('usage: integrations list') unless subcommand == 'list'

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
