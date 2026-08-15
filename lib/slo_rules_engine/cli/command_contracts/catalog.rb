# frozen_string_literal: true

module SloRulesEngine
  module CLI
    module CommandContracts
      module Catalog
        module_function

        def definitions
          @definitions ||= [
            CommandContract.build(
              id: 'providers.list',
              path: %w[providers list],
              human_usage: 'bin/rules-ctl providers list',
              arguments: {},
              side_effect: 'none',
              io: CommandContract.io,
              gates: %w[offline_only],
              output: CommandContract.output(streaming: 'not_applicable'),
              agent_status: 'implemented',
              application_command: 'SloRulesEngine::Application::ListProviders'
            ),
            CommandContract.build(
              id: 'integrations.list',
              path: %w[integrations list],
              human_usage: 'bin/rules-ctl integrations list',
              arguments: {},
              side_effect: 'none',
              io: CommandContract.io,
              gates: %w[offline_only],
              output: CommandContract.output(streaming: 'not_applicable'),
              agent_status: 'implemented',
              application_command: 'SloRulesEngine::Application::ListIntegrations'
            ),
            CommandContract.build(
              id: 'generate-routes',
              human_usage: 'bin/rules-ctl generate-routes --integration=notification_router ./service.rb',
              arguments: {
                integration: CommandContract.argument(
                  example: 'notification_router',
                  schema: CommandSchemas.bounded_string
                ),
                definition_files: CommandContract.argument(
                  example: ['./service.rb'],
                  schema: {
                    type: 'array',
                    minItems: 1,
                    maxItems: 1_000,
                    items: CommandSchemas.bounded_string(pattern: '^[^\u0000-\u001F\u007F]+$')
                  }
                )
              },
              handler: :generate_routes,
              side_effect: 'local_read',
              io: CommandContract.io(local_reads: %w[definitions]),
              gates: %w[strict_arguments neutral_model_validation no_delivery_secrets]
            )
          ].freeze
        end
      end
    end
  end
end
