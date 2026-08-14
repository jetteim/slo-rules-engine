# frozen_string_literal: true

module SloRulesEngine
  module CLI
    module CommandSchemas
      REQUEST_SCHEMA_VERSION = 'slo-rules-engine/agent-command-request/v1'
      PROVIDERS = %w[datadog prometheus_stack sloth].freeze

      module_function

      def request(id:, version:, ref:, example:)
        argument_properties = example.each_with_object({}) do |(name, value), properties|
          properties[name.to_sym] = property_schema(name, value)
        end
        argument_properties.merge!(introspection_properties(id))

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
              required: required_arguments(id, example),
              properties: argument_properties
            }
          }
        }
      end

      def required_arguments(id, example)
        return [] if id == 'agent.catalog'

        example.keys.map(&:to_s)
      end

      def introspection_properties(id)
        case id
        when 'agent.catalog'
          {
            limit: { type: 'integer', minimum: 1, maximum: 100 },
            cursor: bounded_string
          }
        when 'agent.describe'
          { command_id: bounded_string(pattern: '^[a-z][a-z0-9.-]*$') }
        else
          {}
        end
      end

      def property_schema(name, value)
        case value
        when String then string_schema(name)
        when Integer then { type: 'integer', minimum: 0 }
        when Float then { type: 'number', minimum: 0 }
        when TrueClass, FalseClass then { type: 'boolean' }
        when Array then array_schema(name, value)
        when Hash then map_schema(name, value)
        else
          raise ArgumentError, "cannot infer request schema for #{name.inspect}"
        end
      end

      def string_schema(name)
        key = name.to_s
        return bounded_string(enum: PROVIDERS) if key == 'provider'
        return bounded_string(enum: %w[plan live]) if key == 'mode'
        return bounded_string(format: 'uri') if key == 'endpoint' || key.end_with?('_url')
        return bounded_string(format: 'date-time') if %w[from to reviewed_at].include?(key)
        return bounded_string(pattern: '^[^\u0000-\u001F\u007F]+$') if path_name?(key)

        bounded_string
      end

      def array_schema(name, values)
        item_name = name.to_s.sub(/s\z/, '')
        item_schema = values.empty? ? bounded_string : property_schema(item_name, values.first)
        {
          type: 'array',
          minItems: 1,
          maxItems: 1_000,
          items: item_schema
        }
      end

      def map_schema(name, values)
        sample = values.values.first
        value_schema = if sample
                         property_schema(map_value_name(name), sample)
                       else
                         bounded_string
                       end
        {
          type: 'object',
          minProperties: 1,
          maxProperties: 1_000,
          propertyNames: bounded_string(max_length: 512),
          additionalProperties: value_schema
        }
      end

      def map_value_name(name)
        key = name.to_s
        return 'base_url' if key.end_with?('_base_urls')
        return 'file' if key.end_with?('_files')
        return 'dir' if key.end_with?('_outputs')

        'value'
      end

      def path_name?(name)
        name.end_with?('_file') || name.end_with?('_files') || name.end_with?('_dir') ||
          %w[file files path paths].include?(name)
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
