# frozen_string_literal: true

module SloRulesEngine
  module CLI
    module CommandSchemas
      REQUEST_SCHEMA_VERSION = 'slo-rules-engine/agent-command-request/v1'
      PROVIDERS = %w[datadog prometheus_stack sloth].freeze

      module_function

      def request(id:, version:, ref:, argument_properties:, required_arguments:)
        {
          '$schema': 'https://json-schema.org/draft/2020-12/schema',
          '$id': ref,
          type: 'object',
          additionalProperties: false,
          required: %w[schema_version command_id command_version arguments],
          properties: {
            schema_version: { const: REQUEST_SCHEMA_VERSION },
            command_id: { const: id },
            command_version: { const: version },
            arguments: {
              type: 'object',
              additionalProperties: false,
              required: required_arguments,
              properties: argument_properties
            }
          }
        }
      end

      def bounded_string(format: nil, pattern: nil, enum: nil, max_length: 4_096)
        schema = { type: 'string', minLength: 1, maxLength: max_length }
        schema[:format] = format if format
        schema[:pattern] = pattern if pattern
        schema[:enum] = enum if enum
        schema
      end
    end
  end
end
