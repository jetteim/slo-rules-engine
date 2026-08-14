# frozen_string_literal: true

module SloRulesEngine
  module CLI
    class AgentIntrospection
      CATALOG_SCHEMA_VERSION = 'slo-rules-engine/agent-command-catalog/v1'
      DESCRIPTION_SCHEMA_VERSION = 'slo-rules-engine/agent-command-description/v1'
      ERROR_SCHEMA_VERSION = 'slo-rules-engine/agent-command-error/v1'
      DEFAULT_LIMIT = 20
      MAX_LIMIT = 100

      class ContractError < ArgumentError
        attr_reader :code, :details

        def initialize(code, message, details = {})
          @code = code
          @details = details
          super(message)
        end
      end

      def initialize(registry)
        @registry = registry
      end

      def catalog(limit: DEFAULT_LIMIT, cursor: nil)
        limit = normalize_limit(limit)
        definitions = @registry.definitions.sort_by(&:id)
        offset = cursor_offset(definitions, cursor)
        selected = definitions.slice(offset, limit) || []
        truncated = offset + selected.length < definitions.length

        {
          schema_version: CATALOG_SCHEMA_VERSION,
          kind: 'AgentCommandCatalog',
          registry_schema_version: @registry.schema_version,
          total_commands: definitions.length,
          page: {
            limit: limit,
            returned: selected.length,
            cursor: cursor,
            next_cursor: truncated ? selected.last.id : nil,
            truncated: truncated
          },
          commands: selected.map { |definition| compact_command(definition) }
        }
      end

      def describe(id)
        definition = @registry.fetch(id)
        {
          schema_version: DESCRIPTION_SCHEMA_VERSION,
          kind: 'AgentCommandDescription',
          registry_schema_version: @registry.schema_version,
          command: described_command(definition)
        }
      rescue KeyError
        raise ContractError.new(
          'unknown_agent_command',
          'agent command is not registered',
          command_id: id
        )
      end

      def error_payload(error)
        {
          schema_version: ERROR_SCHEMA_VERSION,
          kind: 'AgentCommandError',
          error: {
            code: error.code,
            message: error.message,
            details: error.details
          }
        }
      end

      private

      def normalize_limit(value)
        limit = Integer(value)
        return limit if limit.between?(1, MAX_LIMIT)

        raise ContractError.new(
          'invalid_agent_catalog_limit',
          "catalog limit must be between 1 and #{MAX_LIMIT}",
          minimum: 1,
          maximum: MAX_LIMIT
        )
      rescue ArgumentError, TypeError
        raise ContractError.new(
          'invalid_agent_catalog_limit',
          "catalog limit must be an integer between 1 and #{MAX_LIMIT}",
          minimum: 1,
          maximum: MAX_LIMIT
        )
      end

      def cursor_offset(definitions, cursor)
        return 0 if cursor.nil?

        index = definitions.index { |definition| definition.id == cursor }
        return index + 1 if index

        raise ContractError.new(
          'invalid_agent_catalog_cursor',
          'catalog cursor does not identify a registered command',
          cursor: cursor
        )
      end

      def compact_command(definition)
        {
          id: definition.id,
          version: definition.version,
          human_cli: definition.human_usage,
          agent_cli_json: definition.agent.fetch(:request_example),
          side_effect: definition.side_effect,
          io: definition.io,
          safety_gates: definition.safety_gates,
          schemas: definition.schemas,
          output: definition.output,
          mcp: definition.mcp
        }
      end

      def described_command(definition)
        compact_command(definition).merge(
          human: {
            path: definition.human_path,
            usage: definition.human_usage
          },
          agent: definition.agent,
          handler: definition.handler,
          request_schema: definition.request_schema
        )
      end
    end
  end
end
