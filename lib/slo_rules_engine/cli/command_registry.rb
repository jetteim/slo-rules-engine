# frozen_string_literal: true

require_relative 'command_schemas'
require_relative 'command_contract'
require_relative 'command_contracts/catalog'
require_relative 'command_contracts/analysis'
require_relative 'command_contracts/generation'
require_relative 'command_contracts/provider_state'
require_relative 'command_contracts/telemetry'
require_relative 'command_contracts/onboarding'
require_relative 'command_contracts/approved_plan'
require_relative 'command_contracts/journal'
require_relative 'command_contracts/release_bundle'
require_relative 'command_contracts/introspection'
require_relative 'command_contracts/status'
require_relative 'command_contracts/sloth'

module SloRulesEngine
  module CLI
    class CommandDefinition
      class InvalidDefinition < ArgumentError; end

      SIDE_EFFECT_CLASSES = %w[none local_read local_write provider_read provider_mutation].freeze
      SCHEMA_STATUSES = %w[characterized planned].freeze
      IO_KEYS = %i[local_reads local_writes provider_reads provider_writes credentials].freeze
      OUTPUT_KEYS = %i[stdout persisted_artifacts field_masks streaming].freeze

      attr_reader :id, :version, :human_path, :human_usage, :adapter, :handler, :agent, :schemas,
                  :request_schema, :request_schema_source,
                  :side_effect, :io, :safety_gates, :output, :mcp

      def initialize(id:, version:, human_path:, human_usage:, adapter:, handler:, agent:, schemas:, request_schema:,
                     request_schema_source: 'inferred', side_effect:, io:, safety_gates:, output:, mcp:)
        @id = id
        @version = version
        @human_path = human_path
        @human_usage = human_usage
        @adapter = adapter
        @handler = handler
        @agent = agent
        @schemas = schemas
        @request_schema = request_schema
        @request_schema_source = request_schema_source
        @side_effect = side_effect
        @io = io
        @safety_gates = safety_gates
        @output = output
        @mcp = mcp
        validate!
        instance_variables.each { |name| deep_freeze(instance_variable_get(name)) }
        freeze
      end

      def to_h
        {
          id: id,
          version: version,
          human: {
            path: human_path,
            usage: human_usage,
            adapter: adapter
          },
          handler: handler,
          agent: agent,
          schemas: schemas,
          request_schema: request_schema,
          request_schema_source: request_schema_source,
          side_effect: side_effect,
          io: io,
          safety_gates: safety_gates,
          output: output,
          mcp: mcp
        }
      end

      private

      def validate!
        invalid!('id is required') unless id.is_a?(String) && id.match?(/\A[a-z][a-z0-9.-]*\z/)
        invalid!('version must be a positive integer') unless version.is_a?(Integer) && version.positive?
        unless human_path.is_a?(Array) && !human_path.empty? && human_path.all? { |part| part.is_a?(String) && !part.empty? }
          invalid!('human_path must contain command tokens')
        end
        invalid!('human_usage must be a bin/rules-ctl command') unless human_usage.to_s.start_with?('bin/rules-ctl ')
        invalid!('adapter must be a method symbol') unless adapter.is_a?(Symbol)
        invalid!('handler must be a method symbol') unless handler.is_a?(Symbol)
        validate_agent!
        validate_schemas!
        invalid!('request_schema must be a strict object schema') unless request_schema.is_a?(Hash) &&
                                                                      request_schema[:type] == 'object' &&
                                                                      request_schema[:additionalProperties] == false
        invalid!('request_schema_source must be explicit or inferred') unless %w[explicit inferred].include?(request_schema_source)
        invalid!("unsupported side_effect #{side_effect.inspect}") unless SIDE_EFFECT_CLASSES.include?(side_effect)
        validate_exact_keys!(io, IO_KEYS, 'io')
        io.each { |key, values| invalid!("io.#{key} must be an array") unless values.is_a?(Array) }
        unless safety_gates.is_a?(Array) && !safety_gates.empty? && safety_gates.all? { |gate| gate.is_a?(String) && !gate.empty? }
          invalid!('safety_gates must contain at least one gate')
        end
        validate_exact_keys!(output, OUTPUT_KEYS, 'output')
        invalid!('output.stdout is required') if output[:stdout].to_s.empty?
        invalid!('output.persisted_artifacts must be an array') unless output[:persisted_artifacts].is_a?(Array)
        invalid!('output.field_masks is required') if output[:field_masks].to_s.empty?
        invalid!('output.streaming is required') if output[:streaming].to_s.empty?
        validate_exact_keys!(mcp, %i[eligible status tool_id], 'mcp')
        invalid!('mcp.eligible must be boolean') unless [true, false].include?(mcp[:eligible])
        invalid!('mcp.status is required') if mcp[:status].to_s.empty?
        invalid!('mcp.tool_id is required') if mcp[:tool_id].to_s.empty?
      end

      def validate_agent!
        validate_exact_keys!(agent, %i[command_id status invocation application_command request_example], 'agent')
        invalid!('agent.command_id is required') if agent[:command_id].to_s.empty?
        invalid!('agent.command_id must match id') unless agent[:command_id] == id
        invalid!('agent.status is required') if agent[:status].to_s.empty?
        invalid!('agent.invocation is required') if agent[:invocation].to_s.empty?
        unless agent[:application_command].nil? || agent[:application_command].to_s.start_with?('SloRulesEngine::Application::')
          invalid!('agent.application_command must use the application namespace')
        end
        validate_exact_keys!(
          agent[:request_example],
          %i[schema_version command_id command_version arguments],
          'agent.request_example'
        )
        invalid!('agent.request_example schema is invalid') unless agent[:request_example][:schema_version] == 'slo-rules-engine/agent-command-request/v1'
        invalid!('agent.request_example command_id must match id') unless agent[:request_example][:command_id] == id
        invalid!('agent.request_example command_version must match version') unless agent[:request_example][:command_version] == version
        invalid!('agent.request_example arguments must be an object') unless agent[:request_example][:arguments].is_a?(Hash)
      end

      def validate_schemas!
        validate_exact_keys!(schemas, %i[request result error], 'schemas')
        schemas.each do |name, schema|
          validate_exact_keys!(schema, %i[ref status], "schemas.#{name}")
          invalid!("schemas.#{name}.ref is required") if schema[:ref].to_s.empty?
          unless SCHEMA_STATUSES.include?(schema[:status])
            invalid!("schemas.#{name}.status must be characterized or planned")
          end
        end
      end

      def validate_exact_keys!(value, expected, path)
        invalid!("#{path} must be an object") unless value.is_a?(Hash)
        actual = value.keys
        return if actual.sort_by(&:to_s) == expected.sort_by(&:to_s)

        invalid!("#{path} keys must be #{expected.join(', ')}")
      end

      def invalid!(message)
        raise InvalidDefinition, "invalid command definition #{id.inspect}: #{message}"
      end

      def deep_freeze(value)
        case value
        when Hash
          value.each { |key, item| deep_freeze(key); deep_freeze(item) }
        when Array
          value.each { |item| deep_freeze(item) }
        end
        value.freeze
      end
    end

    class CommandRegistry
      class InvalidRegistry < ArgumentError; end

      SCHEMA_VERSION = 'slo-rules-engine/cli-command-registry/v1'

      attr_reader :schema_version, :definitions

      def self.default
        @default ||= new(CommandCatalog.definitions)
      end

      def initialize(definitions)
        @schema_version = SCHEMA_VERSION
        @definitions = definitions
        validate!
        @by_id = definitions.each_with_object({}) { |definition, result| result[definition.id] = definition }.freeze
        @by_human_path = definitions.each_with_object({}) do |definition, result|
          result[definition.human_path] = definition
        end.freeze
        @root_handlers = definitions.group_by { |definition| definition.human_path.first }.transform_values do |items|
          items.first.adapter
        end.freeze
        definitions.freeze
        freeze
      end

      def fetch(id)
        @by_id.fetch(id)
      end

      def fetch_human(path)
        @by_human_path.fetch(Array(path))
      end

      def find_human(path)
        @by_human_path[Array(path)]
      end

      def handler_for_human_root(root)
        @root_handlers[root]
      end

      def human_paths
        definitions.map(&:human_path)
      end

      def to_h
        {
          schema_version: schema_version,
          commands: definitions.map(&:to_h)
        }
      end

      private

      def validate!
        raise InvalidRegistry, 'command registry requires at least one command' if definitions.empty?
        unless definitions.all? { |definition| definition.is_a?(CommandDefinition) }
          raise InvalidRegistry, 'command registry entries must be CommandDefinition instances'
        end

        duplicate_id = duplicate_value(definitions.map(&:id))
        raise InvalidRegistry, "duplicate command id #{duplicate_id.inspect}" if duplicate_id

        duplicate_path = duplicate_value(definitions.map(&:human_path))
        if duplicate_path
          raise InvalidRegistry, "duplicate Human CLI path #{duplicate_path.join(' ').inspect}"
        end

        definitions.group_by { |definition| definition.human_path.first }.each do |root, items|
          adapters = items.map(&:adapter).uniq
          next if adapters.length == 1

          raise InvalidRegistry, "Human CLI root #{root.inspect} maps to multiple adapters"
        end
      end

      def duplicate_value(values)
        values.group_by(&:itself).find { |_value, matches| matches.length > 1 }&.first
      end
    end

    module CommandCatalog
      SCHEMA_VERSION = 'slo-rules-engine/cli-command-catalog/v1'
      HUMAN_USAGE = {
        'validate-handoff' => 'bin/rules-ctl validate-handoff ./handoff.json',
      }.freeze
      AGENT_ARGUMENT_EXAMPLES = {
        'validate-handoff' => { handoff_file: './handoff.json' },
      }.freeze

      module_function

      def definitions
        @definitions ||= build.freeze
      end

      def to_h
        {
          schema_version: SCHEMA_VERSION,
          commands: definitions.map do |definition|
            {
              id: definition.id,
              human_cli: definition.human_usage,
              agent_cli_json: definition.agent.fetch(:request_example)
            }
          end
        }
      end

      def build
        [
          CommandContracts::Analysis.fetch('validate'),
          command('validate-handoff', handler: :validate_handoff, side_effect: 'local_read',
                  io: io(local_reads: %w[handoff_packet]),
                  gates: %w[strict_arguments handoff_schema reviewed_provenance]),
          *CommandContracts::Generation.definitions,
          *CommandContracts::ProviderState.definitions,
          *CommandContracts::Status.definitions,
          *CommandContracts::Sloth.definitions,
          *CommandContracts::Introspection.definitions,
          *CommandContracts::ReleaseBundle.definitions,
          *CommandContracts::Journal.definitions,
          *CommandContracts::ApprovedPlan.definitions,
          *CommandContracts::Telemetry.definitions,
          *CommandContracts::Catalog.definitions,
          *CommandContracts::Onboarding.definitions,
          CommandContracts::Analysis.fetch('recommend-calculation-basis'),
          CommandContracts::Analysis.fetch('reality-check'),
          *CommandContracts::Analysis.reports
        ]
      end

      def command(id, side_effect:, io:, gates:, path: nil, adapter: nil, handler: nil, output: nil,
                  agent_status: nil, application_command: nil)
        CommandContract.build(
          id: id,
          human_usage: HUMAN_USAGE.fetch(id),
          example: AGENT_ARGUMENT_EXAMPLES.fetch(id),
          side_effect: side_effect,
          io: io,
          gates: gates,
          path: path,
          adapter: adapter,
          handler: handler,
          output: output,
          agent_status: agent_status,
          application_command: application_command
        )
      end

      def io(local_reads: [], local_writes: [], provider_reads: [], provider_writes: [], credentials: [])
        {
          local_reads: local_reads,
          local_writes: local_writes,
          provider_reads: provider_reads,
          provider_writes: provider_writes,
          credentials: credentials
        }
      end

      def output(stdout: 'json', persisted_artifacts: [], field_masks: 'planned', streaming: 'planned')
        {
          stdout: stdout,
          persisted_artifacts: persisted_artifacts,
          field_masks: field_masks,
          streaming: streaming
        }
      end
    end
  end
end
