# frozen_string_literal: true

module SloRulesEngine
  module CLI
    module CommandContracts
      module Onboarding
        IDENTIFIER_SCHEMA = CommandSchemas.bounded_string(
          pattern: '^[a-zA-Z0-9][a-zA-Z0-9_.:-]*$',
          max_length: 512
        ).freeze
        IDENTIFIER_LIST_SCHEMA = {
          type: 'array',
          minItems: 1,
          maxItems: 100,
          items: IDENTIFIER_SCHEMA
        }.freeze

        module_function

        def definitions
          @definitions ||= [
            candidates,
            draft_definition,
            draft_from_handoff,
            onboarding_summary,
            onboarding_artifact_index,
            review_handoff
          ].freeze
        end

        def candidates
          CommandContract.build(
            id: 'candidates',
            human_usage: 'bin/rules-ctl candidates --limit=100 ./telemetry.json',
            arguments: {
              telemetry_file: CommandContract.argument(
                example: './telemetry.json',
                schema: CommandContract.path_schema
              ),
              limit: CommandContract.argument(
                example: 100,
                schema: { type: 'integer', minimum: 1, maximum: 500 },
                required: false
              )
            },
            side_effect: 'local_read',
            io: CommandContract.io(local_reads: %w[telemetry_evidence]),
            gates: %w[
              strict_arguments workspace_confined_agent_reads bounded_input normalized_telemetry
              conservative_classification bounded_response untrusted_text_quarantine read_only
            ],
            output: CommandContract.output(
              field_masks: 'unsafe_telemetry_text_quarantined',
              streaming: 'not_applicable'
            ),
            agent_status: 'implemented',
            application_command: 'SloRulesEngine::Application::ReviewTelemetryCandidates'
          )
        end
        private_class_method :candidates

        def draft_definition
          CommandContract.build(
            id: 'draft-definition',
            human_usage: 'bin/rules-ctl draft-definition --service=checkout --owner=platform ./telemetry.json',
            arguments: {
              service: CommandContract.argument(example: 'checkout', schema: IDENTIFIER_SCHEMA),
              owner: CommandContract.argument(example: 'platform', schema: IDENTIFIER_SCHEMA),
              environment: CommandContract.argument(
                example: 'production',
                schema: IDENTIFIER_SCHEMA,
                required: false,
                include_in_example: false
              ),
              telemetry_file: CommandContract.argument(example: './telemetry.json', schema: CommandContract.path_schema)
            },
            handler: :draft_definition,
            side_effect: 'local_read',
            io: CommandContract.io(local_reads: %w[telemetry_evidence]),
            gates: %w[strict_arguments workspace_confined_agent_reads bounded_input normalized_telemetry review_required],
            output: CommandContract.output(stdout: 'ruby', streaming: 'not_applicable')
          )
        end
        private_class_method :draft_definition

        def draft_from_handoff
          CommandContract.build(
            id: 'draft-from-handoff',
            human_usage: 'bin/rules-ctl draft-from-handoff --service=checkout --owner=platform ./handoff.json',
            arguments: {
              service: CommandContract.argument(example: 'checkout', schema: IDENTIFIER_SCHEMA),
              owner: CommandContract.argument(example: 'platform', schema: IDENTIFIER_SCHEMA),
              environment: CommandContract.argument(
                example: 'production',
                schema: IDENTIFIER_SCHEMA,
                required: false,
                include_in_example: false
              ),
              handoff_file: CommandContract.argument(example: './handoff.json', schema: CommandContract.path_schema)
            },
            handler: :draft_from_handoff,
            side_effect: 'local_read',
            io: CommandContract.io(local_reads: %w[handoff_packet]),
            gates: %w[strict_arguments workspace_confined_agent_reads bounded_input handoff_schema accepted_candidates reviewed_provenance],
            output: CommandContract.output(stdout: 'ruby', streaming: 'not_applicable')
          )
        end
        private_class_method :draft_from_handoff

        def onboarding_summary
          CommandContract.build(
            id: 'onboarding-summary',
            human_usage: 'bin/rules-ctl onboarding-summary --handoff-dir=./handoffs ./discovery/index.json',
            arguments: {
              discovery_index_file: CommandContract.argument(example: './discovery/index.json', schema: CommandContract.path_schema),
              handoff_dir: CommandContract.argument(example: './handoffs', schema: CommandContract.path_schema, required: false)
            },
            handler: :onboarding_summary,
            side_effect: 'local_write',
            io: CommandContract.io(
              local_reads: %w[discovery_index discovery_evidence handoff_packets],
              local_writes: %w[handoff_packets]
            ),
            gates: %w[strict_arguments discovery_schema rerun_safe_review_state]
          )
        end
        private_class_method :onboarding_summary

        def onboarding_artifact_index
          CommandContract.build(
            id: 'onboarding-artifact-index',
            human_usage: 'bin/rules-ctl onboarding-artifact-index --handoff-dir=./handoffs --manifest-dir=./generated --output=./artifact-index.json ./discovery/index.json',
            arguments: {
              discovery_index_file: CommandContract.argument(example: './discovery/index.json', schema: CommandContract.path_schema),
              handoff_dir: CommandContract.argument(example: './handoffs', schema: CommandContract.path_schema, required: false),
              draft_dir: CommandContract.argument(example: './drafts', schema: CommandContract.path_schema, required: false, include_in_example: false),
              manifest_dir: CommandContract.argument(example: './generated', schema: CommandContract.path_schema, required: false),
              providers: CommandContract.argument(
                example: ['prometheus_stack'],
                schema: { type: 'array', minItems: 1, maxItems: 3, items: CommandSchemas.bounded_string(enum: CommandSchemas::PROVIDERS) },
                required: false,
                include_in_example: false
              ),
              output_file: CommandContract.argument(example: './artifact-index.json', schema: CommandContract.path_schema, required: false)
            },
            handler: :onboarding_artifact_index,
            side_effect: 'local_write',
            io: CommandContract.io(
              local_reads: %w[discovery_index discovery_evidence handoff_packets reviewed_definitions provider_manifests manifest_review_reports],
              local_writes: %w[onboarding_artifact_index]
            ),
            gates: %w[strict_arguments artifact_schema evidence_freshness deterministic_index]
          )
        end
        private_class_method :onboarding_artifact_index

        def review_handoff
          CommandContract.build(
            id: 'review-handoff',
            human_usage: 'bin/rules-ctl review-handoff --accept=request-availability --note=Reviewed ./handoff.json',
            arguments: {
              handoff_file: CommandContract.argument(example: './handoff.json', schema: CommandContract.path_schema),
              accept: CommandContract.argument(example: ['request-availability'], schema: IDENTIFIER_LIST_SCHEMA, required: false),
              reject: CommandContract.argument(
                example: ['request-traffic'],
                schema: IDENTIFIER_LIST_SCHEMA,
                required: false,
                include_in_example: false
              ),
              notes: CommandContract.argument(
                example: ['Reviewed'],
                schema: {
                  type: 'array',
                  minItems: 1,
                  maxItems: 100,
                  items: CommandSchemas.bounded_string(max_length: 4_096)
                },
                required: false
              ),
              validate_only: CommandContract.argument(
                example: false,
                schema: { type: 'boolean' },
                required: false,
                include_in_example: false
              )
            },
            handler: :review_handoff,
            side_effect: 'local_write',
            io: CommandContract.io(local_reads: %w[handoff_packet], local_writes: %w[handoff_packet]),
            gates: %w[
              strict_arguments workspace_confined_agent_reads confined_output_file bounded_input
              handoff_schema explicit_review_decision preserve_discovery_evidence credential_text_rejection
              bounded_response untrusted_text_quarantine zero_io_validate_only
            ],
            output: CommandContract.output(
              field_masks: 'bounded_review_summary_with_packet_fingerprint',
              streaming: 'not_applicable'
            ),
            agent_status: 'implemented',
            application_command: 'SloRulesEngine::Application::ReviewOnboardingHandoff'
          )
        end
        private_class_method :review_handoff
      end
    end
  end
end
