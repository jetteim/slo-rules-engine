# frozen_string_literal: true

module SloRulesEngine
  module CLI
    module CommandContracts
      module Status
        module_function

        def definitions
          @definitions ||= [status].freeze
        end

        def status
          CommandContract.build(
            id: "status",
            human_usage: "bin/rules-ctl status --provider=sloth --manifest=./manifest.json --evidence=./sloth-evidence.json --base-url=http://localhost:9090",
            arguments: {
              provider: CommandContract.argument(
                example: "sloth",
                schema: CommandSchemas.bounded_string(enum: CommandSchemas::PROVIDERS)
              ),
              manifest_file: CommandContract.argument(
                example: "./manifest.json",
                schema: CommandContract.path_schema
              ),
              evidence_file: CommandContract.argument(
                example: "./sloth-evidence.json",
                schema: CommandContract.path_schema
              ),
              base_url: CommandContract.argument(
                example: "http://localhost:9090",
                schema: CommandSchemas.bounded_string(format: "uri")
              )
            },
            side_effect: "provider_read",
            io: CommandContract.io(local_reads: ["provider_manifest", "release_bundle", "live_status_portfolio", "sloth_downstream_evidence", "sloth_evidence_sources"],
                                   local_writes: ["live_status_report"],
                                   provider_reads: ["prometheus_instant_queries"]),
            gates: %w[strict_arguments reviewed_manifest exact_manifest_evidence evidence_freshness complete_slo_coverage target_preflight read_only]
          )
        end
        private_class_method :status
      end
    end
  end
end
