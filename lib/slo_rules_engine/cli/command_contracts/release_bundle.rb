# frozen_string_literal: true

module SloRulesEngine
  module CLI
    module CommandContracts
      module ReleaseBundle
        module_function

        def definitions
          @definitions ||= [bundle_create, bundle_plan, bundle_apply, bundle_verify, bundle_status].freeze
        end

        def bundle_create
          CommandContract.build(
            id: "bundle.create",
            human_usage: "bin/rules-ctl bundle create --artifact-index=./index.json --reviewer=reviewer@example.com --reviewed-at=2026-08-04T09:00:00Z --sloth-evidence=checkout/sloth=./sloth-evidence.json --output=./bundle.json",
            arguments: {
              artifact_index_file: CommandContract.argument(
                example: "./index.json",
                schema: CommandContract.path_schema
              ),
              reviewer: CommandContract.argument(
                example: "reviewer@example.com",
                schema: CommandSchemas.bounded_string
              ),
              reviewed_at: CommandContract.argument(
                example: "2026-08-04T09:00:00Z",
                schema: CommandSchemas.bounded_string(format: "date-time")
              ),
              sloth_evidence_files: CommandContract.argument(
                example: { "checkout/sloth" => "./sloth-evidence.json" },
                schema: { type: 'object', minProperties: 1, maxProperties: 1000,
                  propertyNames: CommandSchemas.bounded_string(max_length: 512),
                  additionalProperties: CommandContract.path_schema }
              ),
              output_file: CommandContract.argument(
                example: "./bundle.json",
                schema: CommandContract.path_schema
              )
            },
            side_effect: "local_write",
            io: CommandContract.io(local_reads: ["artifact_index", "provider_plans", "source_evidence"],
                                   local_writes: ["review_ready_bundle"]),
            gates: %w[strict_arguments reviewed_provenance evidence_freshness credential_scan immutable_predecessor]
          )
        end
        private_class_method :bundle_create

        def bundle_plan
          CommandContract.build(
            id: "bundle.plan",
            human_usage: "bin/rules-ctl bundle plan ./bundle.json --target-output=checkout/prometheus_stack=./managed --output=./apply-ready.json",
            arguments: {
              bundle_file: CommandContract.argument(
                example: "./bundle.json",
                schema: CommandContract.path_schema
              ),
              target_outputs: CommandContract.argument(
                example: { "checkout/prometheus_stack" => "./managed" },
                schema: { type: 'object', minProperties: 1, maxProperties: 1000,
                  propertyNames: CommandSchemas.bounded_string(max_length: 512),
                  additionalProperties: CommandSchemas.bounded_string }
              ),
              output_file: CommandContract.argument(
                example: "./apply-ready.json",
                schema: CommandContract.path_schema
              )
            },
            side_effect: "provider_read",
            io: CommandContract.io(local_reads: ["review_ready_bundle", "source_evidence", "managed_files"],
                                   local_writes: ["apply_ready_bundle"],
                                   provider_reads: ["provider_state", "managed_files"],
                                   credentials: ["provider_environment_when_live"]),
            gates: %w[strict_arguments evidence_freshness target_runtime_preflight immutable_predecessor no_provider_mutation]
          )
        end
        private_class_method :bundle_plan

        def bundle_apply
          CommandContract.build(
            id: "bundle.apply",
            human_usage: "bin/rules-ctl bundle apply ./apply-ready.json --confirm --approved-plan=./approved-plan.json --journal-dir=./journals --output=./applied.json",
            arguments: {
              bundle_file: CommandContract.argument(
                example: "./apply-ready.json",
                schema: CommandContract.path_schema
              ),
              confirm: CommandContract.argument(
                example: true,
                schema: { type: "boolean" }
              ),
              approved_plan_files: CommandContract.argument(
                example: ["./approved-plan.json"],
                schema: CommandContract.path_list_schema(max_items: 1_000)
              ),
              journal_dir: CommandContract.argument(
                example: "./journals",
                schema: CommandContract.path_schema
              ),
              output_file: CommandContract.argument(
                example: "./applied.json",
                schema: CommandContract.path_schema
              )
            },
            side_effect: "local_write",
            io: CommandContract.io(local_reads: ["apply_ready_bundle", "approved_plans", "source_evidence", "operation_journals"],
                                   local_writes: ["managed_files", "operation_journals", "provider_state_results", "applied_bundle"],
                                   provider_reads: ["managed_files"],
                                   provider_writes: ["managed_files"]),
            gates: %w[strict_arguments reviewed_provenance evidence_freshness approved_exact_plan explicit_confirmation scope_lock durable_journal post_apply_verification]
          )
        end
        private_class_method :bundle_apply

        def bundle_verify
          CommandContract.build(
            id: "bundle.verify",
            human_usage: "bin/rules-ctl bundle verify ./applied.json --sloth-evidence=checkout/sloth=./sloth-evidence.json --target-base-url=checkout/sloth=http://localhost:9090 --max-age-seconds=300 --output=./verified.json",
            arguments: {
              bundle_file: CommandContract.argument(
                example: "./applied.json",
                schema: CommandContract.path_schema
              ),
              sloth_evidence_files: CommandContract.argument(
                example: { "checkout/sloth" => "./sloth-evidence.json" },
                schema: { type: 'object', minProperties: 1, maxProperties: 1000,
                  propertyNames: CommandSchemas.bounded_string(max_length: 512),
                  additionalProperties: CommandContract.path_schema }
              ),
              target_base_urls: CommandContract.argument(
                example: { "checkout/sloth" => "http://localhost:9090" },
                schema: { type: 'object', minProperties: 1, maxProperties: 1000,
                  propertyNames: CommandSchemas.bounded_string(max_length: 512),
                  additionalProperties: CommandSchemas.bounded_string(format: "uri") }
              ),
              max_age_seconds: CommandContract.argument(
                example: 300,
                schema: { type: "integer", minimum: 0 }
              ),
              output_file: CommandContract.argument(
                example: "./verified.json",
                schema: CommandContract.path_schema
              )
            },
            side_effect: "local_write",
            io: CommandContract.io(local_reads: ["applied_bundle", "approved_plans", "operation_journals", "managed_files", "sloth_downstream_evidence", "sloth_evidence_sources"],
                                   local_writes: ["verified_bundle"],
                                   provider_reads: ["managed_files", "prometheus_instant_queries"]),
            gates: %w[strict_arguments evidence_freshness execution_evidence exact_manifest_evidence complete_slo_coverage target_runtime_preflight read_only_provider_state immutable_predecessor]
          )
        end
        private_class_method :bundle_verify

        def bundle_status
          CommandContract.build(
            id: "bundle.status",
            human_usage: "bin/rules-ctl bundle status ./bundle.json",
            arguments: {
              bundle_file: CommandContract.argument(
                example: "./bundle.json",
                schema: CommandContract.path_schema
              )
            },
            side_effect: "local_read",
            io: CommandContract.io(local_reads: ["release_bundle", "source_evidence"]),
            gates: %w[strict_arguments bundle_schema evidence_freshness read_only]
          )
        end
        private_class_method :bundle_status
      end
    end
  end
end
