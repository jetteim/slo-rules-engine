# frozen_string_literal: true

module SloRulesEngine
  module CLI
    module CommandContracts
      module Journal
        module_function

        def definitions
          @definitions ||= [journal_create, journal_status].freeze
        end

        def journal_create
          CommandContract.build(
            id: "journal.create",
            human_usage: "bin/rules-ctl journal create ./provider-plan.json --output=./journal.json",
            arguments: {
              provider_plan_file: CommandContract.argument(
                example: "./provider-plan.json",
                schema: CommandContract.path_schema
              ),
              output_file: CommandContract.argument(
                example: "./journal.json",
                schema: CommandContract.path_schema
              )
            },
            side_effect: "local_write",
            io: CommandContract.io(local_reads: ["provider_plan"],
                                   local_writes: ["operation_journal"]),
            gates: %w[strict_arguments provider_plan_schema credential_scan no_execution]
          )
        end
        private_class_method :journal_create

        def journal_status
          CommandContract.build(
            id: "journal.status",
            human_usage: "bin/rules-ctl journal status ./journal.json",
            arguments: {
              journal_file: CommandContract.argument(
                example: "./journal.json",
                schema: CommandContract.path_schema
              )
            },
            side_effect: "local_read",
            io: CommandContract.io(local_reads: ["operation_journal"]),
            gates: %w[strict_arguments operation_journal_schema read_only]
          )
        end
        private_class_method :journal_status
      end
    end
  end
end
