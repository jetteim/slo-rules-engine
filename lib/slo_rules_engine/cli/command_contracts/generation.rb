# frozen_string_literal: true

module SloRulesEngine
  module CLI
    module CommandContracts
      module Generation
        module_function

        def definitions
          @definitions ||= [generate, manifest_review].freeze
        end

        def generate
          CommandContract.build(
            id: 'generate',
            human_usage: 'bin/rules-ctl generate --provider=prometheus_stack --output-dir=./generated ./service.rb',
            arguments: {
              provider: CommandContract.argument(
                example: 'prometheus_stack',
                schema: CommandSchemas.bounded_string(enum: CommandSchemas::PROVIDERS)
              ),
              definition_files: CommandContract.argument(
                example: ['./service.rb'],
                schema: CommandContract.path_list_schema
              ),
              output_dir: CommandContract.argument(
                example: './generated',
                schema: CommandContract.path_schema
              ),
              handoff_dir: CommandContract.argument(
                example: './handoffs',
                schema: CommandContract.path_schema,
                required: false,
                include_in_example: false
              ),
              validate_only: CommandContract.argument(
                example: false,
                schema: { type: 'boolean' },
                required: false,
                include_in_example: false
              )
            },
            side_effect: 'local_write',
            io: CommandContract.io(
              local_reads: %w[definitions handoff_packets],
              local_writes: %w[provider_manifests manifest_review_report]
            ),
            gates: %w[
              strict_arguments workspace_confined_agent_reads confined_output_root bounded_input
              neutral_model_validation provider_validation manifest_schema zero_io_validate_only
            ],
            agent_status: 'implemented',
            application_command: 'SloRulesEngine::Application::GenerateProviderManifests'
          )
        end
        private_class_method :generate

        def manifest_review
          CommandContract.build(
            id: 'manifest-review',
            human_usage: 'bin/rules-ctl manifest-review --provider=prometheus_stack --manifest=./manifest.json',
            handler: :manifest_review,
            arguments: {
              provider: CommandContract.argument(
                example: 'prometheus_stack',
                schema: CommandSchemas.bounded_string(enum: CommandSchemas::PROVIDERS)
              ),
              definition_files: CommandContract.argument(
                example: ['./service.rb'],
                schema: CommandContract.path_list_schema,
                required: false,
                include_in_example: false
              ),
              manifest_files: CommandContract.argument(
                example: ['./manifest.json'],
                schema: CommandContract.path_list_schema,
                required: false
              ),
              handoff_dir: CommandContract.argument(
                example: './handoffs',
                schema: CommandContract.path_schema,
                required: false,
                include_in_example: false
              ),
              output_file: CommandContract.argument(
                example: './manifest-review.json',
                schema: CommandContract.path_schema
              ),
              report_file: CommandContract.argument(
                example: './saved-manifest-review.json',
                schema: CommandContract.path_schema,
                required: false,
                include_in_example: false
              ),
              validate_only: CommandContract.argument(
                example: false,
                schema: { type: 'boolean' },
                required: false,
                include_in_example: false
              )
            },
            side_effect: 'local_write',
            io: CommandContract.io(
              local_reads: %w[definitions provider_manifests handoff_packets saved_review_report],
              local_writes: %w[manifest_review_report]
            ),
            gates: %w[
              strict_arguments workspace_confined_agent_reads confined_output_file bounded_input
              manifest_schema reviewed_provenance evidence_freshness zero_io_validate_only
            ],
            agent_status: 'implemented',
            application_command: 'SloRulesEngine::Application::ReviewProviderManifests'
          )
        end
        private_class_method :manifest_review
      end
    end
  end
end
