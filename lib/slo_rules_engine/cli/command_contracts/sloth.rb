# frozen_string_literal: true

module SloRulesEngine
  module CLI
    module CommandContracts
      module Sloth
        module_function

        def definitions
          @definitions ||= [sloth_evidence_capture, sloth_evidence_status, sloth_mcp_compare].freeze
        end

        def sloth_evidence_capture
          CommandContract.build(
            id: "sloth-evidence.capture",
            human_usage: "bin/rules-ctl sloth-evidence capture --manifest=./manifest.json --input=./sloth.yaml --generated-rules=./rules.yaml --reviewer=reviewer@example.com --reviewed-at=2026-08-04T12:00:00Z --output=./sloth-evidence.json",
            arguments: {
              manifest_file: CommandContract.argument(
                example: "./manifest.json",
                schema: CommandContract.path_schema
              ),
              input_files: CommandContract.argument(
                example: ["./sloth.yaml"],
                schema: CommandContract.path_list_schema(max_items: 1_000)
              ),
              generated_rules_file: CommandContract.argument(
                example: "./rules.yaml",
                schema: CommandContract.path_schema
              ),
              reviewer: CommandContract.argument(
                example: "reviewer@example.com",
                schema: CommandSchemas.bounded_string
              ),
              reviewed_at: CommandContract.argument(
                example: "2026-08-04T12:00:00Z",
                schema: CommandSchemas.bounded_string(format: "date-time")
              ),
              output_file: CommandContract.argument(
                example: "./sloth-evidence.json",
                schema: CommandContract.path_schema
              )
            },
            side_effect: "local_write",
            io: CommandContract.io(local_reads: ["reviewed_sloth_manifest", "sloth_native_inputs", "sloth_generated_rules"],
                                   local_writes: ["sloth_downstream_evidence"]),
            gates: %w[strict_arguments reviewed_manifest native_input_parity complete_slo_coverage unambiguous_recording_rules reviewer_attestation credential_scan no_provider_io]
          )
        end
        private_class_method :sloth_evidence_capture

        def sloth_evidence_status
          CommandContract.build(
            id: "sloth-evidence.status",
            human_usage: "bin/rules-ctl sloth-evidence status ./sloth-evidence.json",
            arguments: {
              evidence_file: CommandContract.argument(
                example: "./sloth-evidence.json",
                schema: CommandContract.path_schema
              )
            },
            side_effect: "local_read",
            io: CommandContract.io(local_reads: ["sloth_downstream_evidence", "reviewed_sloth_manifest", "sloth_native_inputs", "sloth_generated_rules"]),
            gates: %w[strict_arguments content_addressed_identity evidence_freshness credential_scan no_provider_io read_only]
          )
        end
        private_class_method :sloth_evidence_status

        def sloth_mcp_compare
          CommandContract.build(
            id: "sloth-mcp.compare",
            human_usage: "bin/rules-ctl sloth-mcp compare --manifest=./manifest.json --evidence=./sloth-evidence.json --endpoint=http://localhost:8080/mcp --allow-host=localhost --expected-version=dev --from=2026-08-01T00:00:00Z --to=2026-08-05T00:00:00Z --output=./sloth-mcp-comparison.json",
            arguments: {
              manifest_file: CommandContract.argument(
                example: "./manifest.json",
                schema: CommandContract.path_schema
              ),
              evidence_file: CommandContract.argument(
                example: "./sloth-evidence.json",
                schema: CommandContract.path_schema
              ),
              endpoint: CommandContract.argument(
                example: "http://localhost:8080/mcp",
                schema: CommandSchemas.bounded_string(format: "uri")
              ),
              allowed_hosts: CommandContract.argument(
                example: ["localhost"],
                schema: { type: 'array', minItems: 1, maxItems: 1000, items: CommandSchemas.bounded_string }
              ),
              expected_version: CommandContract.argument(
                example: "dev",
                schema: CommandSchemas.bounded_string
              ),
              from: CommandContract.argument(
                example: "2026-08-01T00:00:00Z",
                schema: CommandSchemas.bounded_string(format: "date-time")
              ),
              to: CommandContract.argument(
                example: "2026-08-05T00:00:00Z",
                schema: CommandSchemas.bounded_string(format: "date-time")
              ),
              output_file: CommandContract.argument(
                example: "./sloth-mcp-comparison.json",
                schema: CommandContract.path_schema
              )
            },
            side_effect: "provider_read",
            io: CommandContract.io(local_reads: ["reviewed_sloth_manifest", "sloth_downstream_evidence", "sloth_evidence_sources"],
                                   local_writes: ["sloth_mcp_comparison"],
                                   provider_reads: ["sloth_mcp_read_only_tools"]),
            gates: %w[strict_arguments reviewed_manifest exact_manifest_evidence evidence_freshness endpoint_allowlist tested_version pinned_tool_schemas read_only_tool_allowlist exact_sloth_identity bounded_pagination bounded_responses credential_scan no_status_promotion]
          )
        end
        private_class_method :sloth_mcp_compare
      end
    end
  end
end
