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
            ),
            recommend_calculation_basis,
            reality_check
          ].freeze
        end

        def fetch(id)
          definitions.find { |definition| definition.id == id } || raise(KeyError, id)
        end

        def reports
          definitions.select { |definition| %w[migration-report model-report].include?(definition.id) }
        end
        def recommend_calculation_basis
          CommandContract.build(
            id: "recommend-calculation-basis",
            human_usage: "bin/rules-ctl recommend-calculation-basis --observations-per-second=1 --failed-observations-to-alert=5",
            arguments: {
              observations_per_second: CommandContract.argument(
                example: 1.0,
                schema: { type: "number", minimum: 0 }
              ),
              failed_observations_to_alert: CommandContract.argument(
                example: 5.0,
                schema: { type: "number", minimum: 0 }
              )
            },
            side_effect: "none",
            io: CommandContract.io,
            gates: %w[strict_arguments numeric_bounds],
            output: CommandContract.output(streaming: "not_applicable"),
            agent_status: "implemented",
            application_command: "SloRulesEngine::Application::RecommendCalculationBasis"
          )
        end
        private_class_method :recommend_calculation_basis

        def reality_check
          CommandContract.build(
            id: "reality-check",
            human_usage: "bin/rules-ctl reality-check --provider=prometheus_stack --telemetry=./telemetry.json ./service.rb",
            arguments: {
              provider: CommandContract.argument(
                example: "prometheus_stack",
                schema: CommandSchemas.bounded_string(enum: CommandSchemas::PROVIDERS)
              ),
              telemetry_file: CommandContract.argument(
                example: "./telemetry.json",
                schema: CommandContract.path_schema
              ),
              definition_files: CommandContract.argument(
                example: ["./service.rb"],
                schema: CommandContract.path_list_schema(max_items: 1_000)
              )
            },
            side_effect: "provider_read",
            io: CommandContract.io(local_reads: ["definitions", "telemetry_evidence", "lookup_results"],
                                   provider_reads: ["telemetry_backend"],
                                   credentials: ["provider_environment_when_online"]),
            gates: %w[strict_arguments reviewed_provider_binding read_only_backend]
          )
        end
        private_class_method :reality_check
      end
    end
  end
end
