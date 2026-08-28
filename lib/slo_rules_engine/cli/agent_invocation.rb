# frozen_string_literal: true

require 'digest'
require 'json'
require 'stringio'
require 'time'
require 'uri'

module SloRulesEngine
  module CLI
    class AgentRequestValidator
      CONTROL_CHARACTERS = /[\u0000-\u001F\u007F]/

      def validate!(value, schema)
        errors = []
        validate_node(value, schema, '$', errors)
        return value if errors.empty?

        raise AgentIntrospection::ContractError.new(
          'invalid_agent_request',
          'agent request does not match the registered schema',
          errors: errors
        )
      end

      private

      def validate_node(value, schema, path, errors)
        validate_const(value, schema, path, errors)
        validate_enum(value, schema, path, errors)
        case schema_value(schema, :type)
        when 'object' then validate_object(value, schema, path, errors)
        when 'array' then validate_array(value, schema, path, errors)
        when 'string' then validate_string(value, schema, path, errors)
        when 'integer' then validate_number(value, schema, path, errors, integer: true)
        when 'number' then validate_number(value, schema, path, errors, integer: false)
        when 'boolean' then add_type_error(errors, path, 'boolean') unless value == true || value == false
        end
      end

      def validate_object(value, schema, path, errors)
        return add_type_error(errors, path, 'object') unless value.is_a?(Hash)

        properties = schema_value(schema, :properties) || {}
        required = schema_value(schema, :required) || []
        minimum = schema_value(schema, :minProperties)
        maximum = schema_value(schema, :maxProperties)
        add_error(errors, path, 'too_few_properties', "must contain at least #{minimum} properties") if minimum && value.length < minimum
        add_error(errors, path, 'too_many_properties', "must contain at most #{maximum} properties") if maximum && value.length > maximum
        property_names = schema_value(schema, :propertyNames)
        value.each_key { |name| validate_node(name.to_s, property_names, "#{path}.<property>", errors) } if property_names
        required.each do |name|
          add_error(errors, "#{path}.#{name}", 'required', 'required property is missing') unless value.key?(name.to_s)
        end
        additional_properties = schema_value(schema, :additionalProperties)
        value.each do |name, item|
          property_schema = properties[name.to_sym] || properties[name.to_s]
          if property_schema
            validate_node(item, property_schema, "#{path}.#{name}", errors)
          elsif additional_properties == false
            add_error(errors, "#{path}.#{name}", 'unknown_property', 'property is not allowed')
          elsif additional_properties.is_a?(Hash)
            validate_node(item, additional_properties, "#{path}.#{name}", errors)
          end
        end
      end

      def validate_array(value, schema, path, errors)
        return add_type_error(errors, path, 'array') unless value.is_a?(Array)

        minimum = schema_value(schema, :minItems)
        maximum = schema_value(schema, :maxItems)
        add_error(errors, path, 'too_few_items', "must contain at least #{minimum} items") if minimum && value.length < minimum
        add_error(errors, path, 'too_many_items', "must contain at most #{maximum} items") if maximum && value.length > maximum
        item_schema = schema_value(schema, :items)
        value.each_with_index { |item, index| validate_node(item, item_schema, "#{path}[#{index}]", errors) } if item_schema
      end

      def validate_string(value, schema, path, errors)
        return add_type_error(errors, path, 'string') unless value.is_a?(String)

        add_error(errors, path, 'control_character', 'must not contain control characters') if value.match?(CONTROL_CHARACTERS)
        minimum = schema_value(schema, :minLength)
        maximum = schema_value(schema, :maxLength)
        add_error(errors, path, 'too_short', "must contain at least #{minimum} characters") if minimum && value.length < minimum
        add_error(errors, path, 'too_long', "must contain at most #{maximum} characters") if maximum && value.length > maximum
        pattern = schema_value(schema, :pattern)
        add_error(errors, path, 'pattern_mismatch', 'does not match the required pattern') if pattern && !Regexp.new(pattern).match?(value)
        validate_format(value, schema_value(schema, :format), path, errors)
      end

      def validate_number(value, schema, path, errors, integer:)
        valid_type = integer ? value.is_a?(Integer) : value.is_a?(Numeric)
        return add_type_error(errors, path, integer ? 'integer' : 'number') unless valid_type

        minimum = schema_value(schema, :minimum)
        maximum = schema_value(schema, :maximum)
        add_error(errors, path, 'below_minimum', "must be at least #{minimum}") if minimum && value < minimum
        add_error(errors, path, 'above_maximum', "must be at most #{maximum}") if maximum && value > maximum
      end

      def validate_const(value, schema, path, errors)
        expected = schema_value(schema, :const)
        return if expected.nil? || value == expected

        add_error(errors, path, 'const_mismatch', 'does not match the required constant')
      end

      def validate_enum(value, schema, path, errors)
        allowed = schema_value(schema, :enum)
        return if allowed.nil? || allowed.include?(value)

        add_error(errors, path, 'enum_mismatch', 'is not an allowed value')
      end

      def validate_format(value, format, path, errors)
        return unless format

        valid = case format
                when 'uri'
                  uri = URI.parse(value)
                  !uri.scheme.to_s.empty?
                when 'date-time'
                  Time.iso8601(value)
                  true
                else
                  true
                end
        add_error(errors, path, 'invalid_format', "must use #{format} format") unless valid
      rescue URI::InvalidURIError, ArgumentError
        add_error(errors, path, 'invalid_format', "must use #{format} format")
      end

      def schema_value(schema, key)
        return schema[key] if schema.key?(key)

        schema[key.to_s]
      end

      def add_type_error(errors, path, expected)
        add_error(errors, path, 'type_mismatch', "must be a JSON #{expected}")
      end

      def add_error(errors, path, code, message)
        errors << { path: path, code: code, message: message }
      end
    end

    class AgentInvocation
      RESULT_SCHEMA_VERSION = 'slo-rules-engine/agent-command-result/v1'
      MAX_REQUEST_BYTES = 1_048_576
      SUPPORTED_FORMATS = %w[json].freeze

      def initialize(registry:, application_context:)
        @registry = registry
        @application_context = application_context
        @validator = AgentRequestValidator.new
      end

      def parse_request(raw)
        if raw.bytesize > MAX_REQUEST_BYTES
          raise AgentIntrospection::ContractError.new(
            'agent_request_too_large',
            "agent request must not exceed #{MAX_REQUEST_BYTES} bytes",
            maximum_bytes: MAX_REQUEST_BYTES
          )
        end

        value = JSON.parse(raw)
        return value if value.is_a?(Hash)

        raise AgentIntrospection::ContractError.new(
          'invalid_agent_request',
          'agent request must be a JSON object'
        )
      rescue JSON::ParserError => error
        raise AgentIntrospection::ContractError.new(
          'malformed_agent_json',
          'agent request is not valid JSON',
          parser_error: error.message.split(':').first
        )
      end

      def read_request_file(path, workspace_root: Dir.pwd)
        root = File.realpath(workspace_root)
        resolved = File.realpath(File.expand_path(path, root))
        unless resolved == root || resolved.start_with?("#{root}#{File::SEPARATOR}")
          raise AgentIntrospection::ContractError.new(
            'unsafe_agent_request_path',
            'agent request file must remain inside the current workspace'
          )
        end

        File.read(resolved, MAX_REQUEST_BYTES + 1)
      rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP, Errno::EISDIR => error
        raise AgentIntrospection::ContractError.new(
          'unreadable_agent_request_file',
          'agent request file cannot be read',
          reason: error.class.name
        )
      end

      def invoke(command_id, request, format:)
        validate_format!(format)
        request_id = request_id(request)
        definition = fetch_definition(command_id)
        @validator.validate!(request, definition.request_schema)
        application_command = definition.agent.fetch(:application_command)
        unless definition.agent.fetch(:status) == 'implemented' && application_command
          raise AgentIntrospection::ContractError.new(
            'agent_command_not_executable',
            'agent command is registered but not executable through structured invocation',
            command_id: command_id,
            side_effect: definition.side_effect,
            required_feature: required_feature(definition)
          )
        end

        result = execute_application_command(application_command, request.fetch('arguments'))
        unless result.is_a?(SloRulesEngine::Application::CommandResult)
          raise AgentIntrospection::ContractError.new(
            'invalid_application_result',
            'application command did not return a typed result'
          )
        end
        unless valid_side_effect_evidence?(definition, request, result)
          raise AgentIntrospection::ContractError.new(
            'application_side_effect_mismatch',
            'application command side-effect evidence does not match its declaration',
            declared: definition.side_effect,
            exercised: result.side_effect
          )
        end
        result_payload(definition, request_id, result)
      rescue AgentIntrospection::ContractError => error
        error.attach_request_id(request_id) if defined?(request_id) && request_id
        raise
      rescue SloRulesEngine::Application::InputSafety::Error,
             SloRulesEngine::Application::CommandError => error
        contract_error = AgentIntrospection::ContractError.new(error.code, error.message, error.details)
        contract_error.attach_request_id(request_id) if defined?(request_id) && request_id
        raise contract_error
      rescue SloRulesEngine::ManifestSchemaError => error
        contract_error = AgentIntrospection::ContractError.new(
          'invalid_manifest_schema',
          'manifest input does not match the reviewed manifest contract',
          errors: error.result.errors.map(&:to_h),
          warnings: error.result.warnings.map(&:to_h)
        )
        contract_error.attach_request_id(request_id) if defined?(request_id) && request_id
        raise contract_error
      rescue ArgumentError => error
        contract_error = AgentIntrospection::ContractError.new(
          'invalid_application_command',
          'normalized application command rejected the request',
          error_class: error.class.name
        )
        contract_error.attach_request_id(request_id) if defined?(request_id) && request_id
        raise contract_error
      rescue StandardError => error
        contract_error = AgentIntrospection::ContractError.new(
          'application_command_failed',
          'application command failed without producing a result',
          error_class: error.class.name
        )
        contract_error.attach_request_id(request_id) if defined?(request_id) && request_id
        raise contract_error
      end

      private

      def valid_side_effect_evidence?(definition, request, result)
        return true if result.side_effect == definition.side_effect

        request.dig('arguments', 'validate_only') == true &&
          definition.safety_gates.include?('zero_io_validate_only') &&
          result.side_effect == 'none'
      end

      def fetch_definition(command_id)
        @registry.fetch(command_id)
      rescue KeyError
        raise AgentIntrospection::ContractError.new(
          'unknown_agent_command',
          'agent command is not registered',
          command_id: command_id
        )
      end

      def validate_format!(format)
        return if SUPPORTED_FORMATS.include?(format)

        raise AgentIntrospection::ContractError.new(
          'unsupported_agent_output_format',
          'agent output format is not supported',
          format: format,
          supported_formats: SUPPORTED_FORMATS
        )
      end

      def required_feature(definition)
        return 'AICLI-F3' unless definition.side_effect == 'none'

        'AICLI-F2'
      end

      def resolve_application_command(name)
        unless name.start_with?('SloRulesEngine::Application::')
          raise AgentIntrospection::ContractError.new(
            'invalid_agent_command_mapping',
            'registered application command is outside the allowed namespace'
          )
        end

        name.split('::').reject(&:empty?).inject(Object) { |scope, constant| scope.const_get(constant, false) }
      rescue NameError
        raise AgentIntrospection::ContractError.new(
          'invalid_agent_command_mapping',
          'registered application command cannot be resolved'
        )
      end

      def execute_application_command(name, arguments)
        stdout = StringIO.new
        stderr = StringIO.new
        original_stdout = $stdout
        original_stderr = $stderr
        $stdout = stdout
        $stderr = stderr
        result = resolve_application_command(name).new.call(arguments, context: @application_context)
        unless stdout.string.empty? && stderr.string.empty?
          raise AgentIntrospection::ContractError.new(
            'unexpected_application_output',
            'application command emitted output outside its typed result',
            stdout_bytes: stdout.string.bytesize,
            stderr_bytes: stderr.string.bytesize
          )
        end
        result
      rescue SystemExit => error
        raise AgentIntrospection::ContractError.new(
          'unexpected_application_exit',
          'application command attempted to terminate the process',
          exit_status: error.status
        )
      ensure
        $stdout = original_stdout
        $stderr = original_stderr
      end

      def request_id(request)
        canonical = canonicalize(request)
        "req-#{Digest::SHA256.hexdigest(JSON.generate(canonical))[0, 24]}"
      end

      def canonicalize(value)
        case value
        when Hash
          value.keys.sort.each_with_object({}) { |key, result| result[key] = canonicalize(value.fetch(key)) }
        when Array
          value.map { |item| canonicalize(item) }
        else
          value
        end
      end

      def result_payload(definition, request_id, result)
        {
          schema_version: RESULT_SCHEMA_VERSION,
          kind: 'AgentCommandResult',
          request_id: request_id,
          command_id: definition.id,
          command_version: definition.version,
          outcome: result.exit_status.zero? ? 'succeeded' : 'failed',
          exit_status: result.exit_status,
          side_effect: {
            declared: definition.side_effect,
            exercised: result.side_effect
          },
          result: result.value,
          findings: result.findings,
          artifacts: result.artifacts,
          truncation: result.truncation
        }
      end
    end
  end
end
