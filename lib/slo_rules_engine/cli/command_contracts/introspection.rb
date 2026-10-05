# frozen_string_literal: true

module SloRulesEngine
  module CLI
    module CommandContracts
      module Introspection
        module_function

        def definitions
          @definitions ||= [agent_catalog, agent_describe].freeze
        end

        def agent_catalog
          CommandContract.build(
            id: "agent.catalog",
            human_usage: "bin/rules-ctl agent catalog --format=json --limit=20",
            arguments: {
              limit: CommandContract.argument(
                example: 20,
                schema: { type: "integer", minimum: 1, maximum: 100 },
                required: false
              ),
              cursor: CommandContract.argument(
                example: nil,
                schema: CommandSchemas.bounded_string,
                required: false,
                include_in_example: false
              )
            },
            side_effect: "none",
            io: CommandContract.io,
            gates: %w[strict_arguments offline_only bounded_pagination deterministic_output],
            output: CommandContract.output(streaming: "not_applicable")
          )
        end
        private_class_method :agent_catalog

        def agent_describe
          CommandContract.build(
            id: "agent.describe",
            human_usage: "bin/rules-ctl agent describe bundle.verify --format=json",
            arguments: {
              command_id: CommandContract.argument(
                example: "bundle.verify",
                schema: CommandSchemas.bounded_string(pattern: "^[a-z][a-z0-9.-]*$")
              )
            },
            side_effect: "none",
            io: CommandContract.io,
            gates: %w[strict_arguments offline_only exact_command_id deterministic_output],
            output: CommandContract.output(streaming: "not_applicable")
          )
        end
        private_class_method :agent_describe
      end
    end
  end
end
