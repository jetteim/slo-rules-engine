# frozen_string_literal: true

module SloRulesEngine
  module CLI
    module CommandContracts
      module Analysis
        module_function

        def definitions
          @definitions ||= [
            CommandContract.build(
              id: 'validate',
              human_usage: 'bin/rules-ctl validate ./service.rb',
              arguments: {
                definition_files: CommandContract.argument(
                  example: ['./service.rb'],
                  schema: CommandContract.path_list_schema
                )
              },
              side_effect: 'local_read',
              io: CommandContract.io(local_reads: %w[definitions]),
              gates: %w[strict_arguments workspace_confined_agent_reads bounded_input neutral_model_validation],
              agent_status: 'implemented',
              application_command: 'SloRulesEngine::Application::ValidateDefinitions'
            ),
            CommandContract.build(
              id: 'migration-report',
              human_usage: 'bin/rules-ctl migration-report ./legacy.rb',
              handler: :migration_report,
              arguments: {
                legacy_files: CommandContract.argument(
                  example: ['./legacy.rb'],
                  schema: CommandContract.path_list_schema
                )
              },
              side_effect: 'local_read',
              io: CommandContract.io(local_reads: %w[legacy_definitions]),
              gates: %w[strict_arguments workspace_confined_agent_reads bounded_input public_safe_reporting],
              agent_status: 'implemented',
              application_command: 'SloRulesEngine::Application::BuildMigrationReport'
            ),
            CommandContract.build(
              id: 'model-report',
              human_usage: 'bin/rules-ctl model-report ./service.rb',
              handler: :model_report,
              arguments: {
                definition_files: CommandContract.argument(
                  example: ['./service.rb'],
                  schema: CommandContract.path_list_schema
                )
              },
              side_effect: 'local_read',
              io: CommandContract.io(local_reads: %w[definitions]),
              gates: %w[strict_arguments workspace_confined_agent_reads bounded_input neutral_model_validation reviewed_provenance_visibility],
              agent_status: 'implemented',
              application_command: 'SloRulesEngine::Application::BuildModelReport'
            )
          ].freeze
        end

        def fetch(id)
          definitions.find { |definition| definition.id == id } || raise(KeyError, id)
        end

        def reports
          definitions.drop(1)
        end
      end
    end
  end
end
