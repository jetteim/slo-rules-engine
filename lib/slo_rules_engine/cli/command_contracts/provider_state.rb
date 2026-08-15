# frozen_string_literal: true

module SloRulesEngine
  module CLI
    module CommandContracts
      module ProviderState
        module_function

        def definitions
          @definitions ||= [
            CommandContract.build(
              id: 'apply',
              human_usage: 'bin/rules-ctl apply --provider=datadog --dry-run --manifest=./manifest.json',
              arguments: state_mutation_arguments,
              side_effect: 'provider_mutation',
              io: CommandContract.io(
                local_reads: %w[definitions provider_manifests handoff_packets saved_review_report operation_journal],
                local_writes: %w[managed_files operation_journal provider_state_result],
                provider_reads: %w[provider_state managed_files],
                provider_writes: %w[provider_state managed_files],
                credentials: %w[provider_environment_when_live]
              ),
              gates: %w[strict_arguments reviewed_manifest reviewed_provenance evidence_freshness managed_ownership explicit_confirmation durable_journal post_apply_verification]
            ),
            CommandContract.build(
              id: 'diff',
              human_usage: 'bin/rules-ctl diff --provider=prometheus_stack --manifest=./manifest.json --output-dir=./managed',
              arguments: {
                provider: CommandContract.argument(
                  example: 'prometheus_stack',
                  schema: CommandSchemas.bounded_string(enum: %w[prometheus_stack sloth])
                ),
                manifest_file: CommandContract.argument(
                  example: './manifest.json',
                  schema: CommandContract.path_schema
                ),
                output_dir: CommandContract.argument(
                  example: './managed',
                  schema: CommandContract.path_schema
                )
              },
              side_effect: 'provider_read',
              io: CommandContract.io(
                local_reads: %w[provider_manifests managed_files],
                provider_reads: %w[managed_files]
              ),
              gates: %w[strict_arguments workspace_confined_agent_reads bounded_input reviewed_manifest provider_validation read_only no_provider_network],
              agent_status: 'implemented',
              application_command: 'SloRulesEngine::Application::DiffProviderState'
            ),
            CommandContract.build(
              id: 'import',
              human_usage: 'bin/rules-ctl import --provider=datadog --manifest=./manifest.json',
              handler: :import_existing,
              arguments: state_read_arguments,
              side_effect: 'provider_read',
              io: CommandContract.io(
                local_reads: %w[definitions provider_manifests managed_files],
                provider_reads: %w[provider_state managed_files],
                credentials: %w[provider_environment_when_live]
              ),
              gates: %w[strict_arguments provider_validation managed_ownership read_only]
            ),
            CommandContract.build(
              id: 'prune',
              human_usage: 'bin/rules-ctl prune --provider=datadog --dry-run --manifest=./manifest.json',
              arguments: state_mutation_arguments,
              side_effect: 'provider_mutation',
              io: CommandContract.io(
                local_reads: %w[definitions provider_manifests handoff_packets saved_review_report operation_journal],
                local_writes: %w[managed_files operation_journal provider_state_result],
                provider_reads: %w[provider_state managed_files],
                provider_writes: %w[provider_state managed_files],
                credentials: %w[provider_environment_when_live]
              ),
              gates: %w[strict_arguments reviewed_manifest reviewed_provenance evidence_freshness managed_ownership explicit_confirmation durable_journal post_apply_verification]
            )
          ].freeze
        end

        def state_read_arguments
          {
            provider: CommandContract.argument(
              example: 'datadog',
              schema: CommandSchemas.bounded_string(enum: CommandSchemas::PROVIDERS)
            ),
            manifest_file: CommandContract.argument(
              example: './manifest.json',
              schema: CommandContract.path_schema
            ),
            output_dir: CommandContract.argument(
              example: './managed',
              schema: CommandContract.path_schema,
              required: false,
              include_in_example: false
            )
          }
        end
        private_class_method :state_read_arguments

        def state_mutation_arguments
          state_read_arguments.merge(
            mode: CommandContract.argument(
              example: 'plan',
              schema: CommandSchemas.bounded_string(enum: %w[plan live])
            ),
            journal_dir: CommandContract.argument(
              example: './journals',
              schema: CommandContract.path_schema,
              required: false,
              include_in_example: false
            ),
            handoff_dir: CommandContract.argument(
              example: './handoffs',
              schema: CommandContract.path_schema,
              required: false,
              include_in_example: false
            ),
            review_report_file: CommandContract.argument(
              example: './manifest-review.json',
              schema: CommandContract.path_schema,
              required: false,
              include_in_example: false
            )
          )
        end
        private_class_method :state_mutation_arguments
      end
    end
  end
end
