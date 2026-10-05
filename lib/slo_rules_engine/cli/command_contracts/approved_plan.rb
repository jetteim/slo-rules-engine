# frozen_string_literal: true

module SloRulesEngine
  module CLI
    module CommandContracts
      module ApprovedPlan
        module_function

        def definitions
          @definitions ||= [plan_approve, plan_status, plan_apply, plan_resume].freeze
        end

        def plan_approve
          CommandContract.build(
            id: "plan.approve",
            human_usage: "bin/rules-ctl plan approve ./apply-ready.json --target=checkout/prometheus_stack --reviewer=reviewer@example.com --reviewed-at=2026-08-04T09:00:00Z --output=./approved-plan.json",
            arguments: {
              bundle_file: CommandContract.argument(
                example: "./apply-ready.json",
                schema: CommandContract.path_schema
              ),
              target: CommandContract.argument(
                example: "checkout/prometheus_stack",
                schema: CommandSchemas.bounded_string
              ),
              reviewer: CommandContract.argument(
                example: "reviewer@example.com",
                schema: CommandSchemas.bounded_string
              ),
              reviewed_at: CommandContract.argument(
                example: "2026-08-04T09:00:00Z",
                schema: CommandSchemas.bounded_string(format: "date-time")
              ),
              output_file: CommandContract.argument(
                example: "./approved-plan.json",
                schema: CommandContract.path_schema
              )
            },
            side_effect: "local_write",
            io: CommandContract.io(local_reads: ["apply_ready_bundle", "source_evidence", "provider_plan"],
                                   local_writes: ["approved_plan"]),
            gates: %w[strict_arguments reviewed_provenance evidence_freshness reviewer_attestation credential_scan]
          )
        end
        private_class_method :plan_approve

        def plan_status
          CommandContract.build(
            id: "plan.status",
            human_usage: "bin/rules-ctl plan status ./approved-plan.json",
            arguments: {
              approved_plan_file: CommandContract.argument(
                example: "./approved-plan.json",
                schema: CommandContract.path_schema
              )
            },
            side_effect: "local_read",
            io: CommandContract.io(local_reads: ["approved_plan", "source_evidence", "managed_files"]),
            gates: %w[strict_arguments approved_plan_schema evidence_freshness managed_path_containment read_only]
          )
        end
        private_class_method :plan_status

        def plan_apply
          CommandContract.build(
            id: "plan.apply",
            human_usage: "bin/rules-ctl plan apply ./approved-plan.json --confirm --journal-dir=./journals",
            arguments: {
              approved_plan_file: CommandContract.argument(
                example: "./approved-plan.json",
                schema: CommandContract.path_schema
              ),
              confirm: CommandContract.argument(
                example: true,
                schema: { type: "boolean" }
              ),
              journal_dir: CommandContract.argument(
                example: "./journals",
                schema: CommandContract.path_schema
              )
            },
            side_effect: "local_write",
            io: CommandContract.io(local_reads: ["approved_plan", "source_evidence", "managed_files", "operation_journal"],
                                   local_writes: ["managed_files", "operation_journal", "provider_state_result"],
                                   provider_reads: ["managed_files"],
                                   provider_writes: ["managed_files"]),
            gates: %w[strict_arguments reviewed_provenance evidence_freshness approved_exact_plan explicit_confirmation scope_lock durable_journal post_apply_verification]
          )
        end
        private_class_method :plan_apply

        def plan_resume
          CommandContract.build(
            id: "plan.resume",
            human_usage: "bin/rules-ctl plan resume ./approved-plan.json --confirm --journal-dir=./journals",
            arguments: {
              approved_plan_file: CommandContract.argument(
                example: "./approved-plan.json",
                schema: CommandContract.path_schema
              ),
              confirm: CommandContract.argument(
                example: true,
                schema: { type: "boolean" }
              ),
              journal_dir: CommandContract.argument(
                example: "./journals",
                schema: CommandContract.path_schema
              )
            },
            side_effect: "local_write",
            io: CommandContract.io(local_reads: ["approved_plan", "source_evidence", "managed_files", "operation_journal"],
                                   local_writes: ["managed_files", "operation_journal", "provider_state_result"],
                                   provider_reads: ["managed_files"],
                                   provider_writes: ["managed_files"]),
            gates: %w[strict_arguments approved_exact_plan resumable_journal state_recheck explicit_confirmation scope_lock post_apply_verification]
          )
        end
        private_class_method :plan_resume
      end
    end
  end
end
