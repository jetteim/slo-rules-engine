# frozen_string_literal: true

module SloRulesEngine
  module CLI
    module CommandContract
      module_function

      def build(id:, human_usage:, side_effect:, io:, gates:, path: nil, adapter: nil, handler: nil,
                output: nil, example: nil, arguments: nil, agent_status: nil, application_command: nil)
        human_path = path || id.split('.')
        handler ||= id.tr('.-', '_').to_sym
        adapter ||= human_path.length == 1 ? handler : human_path.first.tr('-', '_').to_sym
        contract_prefix = "slo-rules-engine/cli-command-contract/#{id}"
        request_ref = "#{contract_prefix}/request/v1"
        explicit = !arguments.nil?
        request_example, argument_properties, required_arguments = normalize_arguments(arguments, example)

        CommandDefinition.new(
          id: id,
          version: 1,
          human_path: human_path,
          human_usage: human_usage,
          adapter: adapter,
          handler: handler,
          agent: {
            command_id: id,
            status: agent_status || (id.start_with?('agent.') ? 'implemented' : 'planned'),
            invocation: "rules-ctl agent invoke #{id}",
            application_command: application_command,
            request_example: {
              schema_version: CommandSchemas::REQUEST_SCHEMA_VERSION,
              command_id: id,
              command_version: 1,
              arguments: request_example
            }
          },
          schemas: {
            request: { ref: request_ref, status: 'characterized' },
            result: { ref: "#{contract_prefix}/result/v1", status: 'characterized' },
            error: { ref: "#{contract_prefix}/error/v1", status: 'characterized' }
          },
          request_schema: CommandSchemas.request(
            id: id,
            version: 1,
            ref: request_ref,
            example: request_example,
            argument_properties: argument_properties,
            explicit_required_arguments: required_arguments
          ),
          request_schema_source: explicit ? 'explicit' : 'inferred',
          side_effect: side_effect,
          io: io,
          safety_gates: gates,
          output: output || output(persisted_artifacts: io[:local_writes]),
          mcp: {
            eligible: true,
            status: 'planned',
            tool_id: id.tr('.-', '_')
          }
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

      def argument(example:, schema:, required: true, include_in_example: true)
        {
          example: example,
          schema: schema,
          required: required,
          include_in_example: include_in_example
        }
      end

      def path_schema
        CommandSchemas.bounded_string(pattern: '^[^\u0000-\u001F\u007F]+$')
      end

      def path_list_schema(max_items: 100)
        {
          type: 'array',
          minItems: 1,
          maxItems: max_items,
          items: path_schema
        }
      end

      def normalize_arguments(arguments, example)
        return [example, nil, nil] unless arguments

        request_example = arguments.each_with_object({}) do |(name, definition), result|
          next unless definition.fetch(:include_in_example)

          result[name] = definition.fetch(:example)
        end
        properties = arguments.transform_values { |definition| definition.fetch(:schema) }
        required = arguments.filter_map { |name, definition| name.to_s if definition.fetch(:required) }
        [request_example, properties, required]
      end
      private_class_method :normalize_arguments
    end
  end
end
