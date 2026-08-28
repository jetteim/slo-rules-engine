# frozen_string_literal: true

module SloRulesEngine
  module CLI
    module CommandContracts
      module Telemetry
        LIMIT_SCHEMA = { type: 'integer', minimum: 1, maximum: 500 }.freeze
        TIMESTAMP_SCHEMA = { type: 'integer', minimum: 0 }.freeze
        HOST_SCHEMA = CommandSchemas.bounded_string(
          pattern: '^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$|^[a-zA-Z0-9]$'
        ).freeze
        SELECTORS_SCHEMA = {
          type: 'object',
          minProperties: 1,
          maxProperties: 20,
          propertyNames: CommandSchemas.bounded_string(
            pattern: '^[a-zA-Z_][a-zA-Z0-9_.-]*$',
            max_length: 512
          ),
          additionalProperties: CommandSchemas.bounded_string(
            pattern: '^[a-zA-Z0-9_.:-]+$',
            max_length: 512
          )
        }.freeze

        module_function

        def definitions
          @definitions ||= [lookup, discover].freeze
        end

        def lookup
          CommandContract.build(
            id: 'lookup-telemetry',
            human_usage: 'bin/rules-ctl lookup-telemetry --provider=prometheus_stack --metric=http_requests_total --base-url=http://localhost:9090 --allow-host=localhost',
            arguments: common_arguments.merge(
              metric: CommandContract.argument(
                example: 'http_requests_total',
                schema: CommandSchemas.bounded_string(max_length: 512)
              ),
              kind: CommandContract.argument(
                example: 'traffic',
                schema: CommandSchemas.bounded_string(
                  enum: %w[unknown latency errors availability traffic freshness user_journey saturation]
                ),
                required: false
              ),
              query: CommandContract.argument(
                example: 'sum(rate(http_requests_total[5m]))',
                schema: CommandSchemas.bounded_string(max_length: 16_384),
                required: false,
                include_in_example: false
              ),
              user_visible: CommandContract.argument(
                example: true,
                schema: { type: 'boolean' },
                required: false,
                include_in_example: false
              )
            ),
            side_effect: 'provider_read',
            io: CommandContract.io(
              provider_reads: %w[telemetry_backend],
              credentials: %w[provider_environment_when_required]
            ),
            gates: %w[
              strict_arguments endpoint_allowlist exact_resource_identifiers bounded_query
              bounded_response sanitized_provider_errors read_only zero_io_validate_only
            ],
            output: CommandContract.output(field_masks: 'credential_and_provider_text_sanitized', streaming: 'not_applicable'),
            agent_status: 'implemented',
            application_command: 'SloRulesEngine::Application::LookupTelemetry'
          )
        end
        private_class_method :lookup

        def discover
          CommandContract.build(
            id: 'discover-telemetry',
            human_usage: 'bin/rules-ctl discover-telemetry --provider=prometheus_stack --service=checkout --base-url=http://localhost:9090 --allow-host=localhost --limit=100',
            arguments: common_arguments.merge(
              service: CommandContract.argument(
                example: 'checkout',
                schema: CommandSchemas.bounded_string(pattern: '^[a-zA-Z0-9_.:-]+$', max_length: 512),
                required: false
              ),
              selectors: CommandContract.argument(
                example: { 'environment' => 'production' },
                schema: SELECTORS_SCHEMA,
                required: false,
                include_in_example: false
              ),
              host: CommandContract.argument(
                example: 'checkout-01.example.com',
                schema: CommandSchemas.bounded_string(pattern: '^[a-zA-Z0-9][a-zA-Z0-9.:-]*$', max_length: 512),
                required: false,
                include_in_example: false
              ),
              scope_file: CommandContract.argument(
                example: './discovery-scopes.json',
                schema: CommandContract.path_schema,
                required: false,
                include_in_example: false
              ),
              output_dir: CommandContract.argument(
                example: './discovery',
                schema: CommandContract.path_schema,
                required: false,
                include_in_example: false
              ),
              limit: CommandContract.argument(example: 100, schema: LIMIT_SCHEMA)
            ),
            side_effect: 'provider_read',
            io: CommandContract.io(
              local_reads: %w[scope_file],
              local_writes: %w[discovery_evidence discovery_index],
              provider_reads: %w[telemetry_backend],
              credentials: %w[provider_environment_when_required]
            ),
            gates: %w[
              strict_arguments workspace_confined_agent_reads confined_output_root endpoint_allowlist
              exact_resource_identifiers bounded_scope bounded_response sanitized_provider_errors
              one_provider_per_run read_only_backend zero_io_validate_only
            ],
            output: CommandContract.output(
              persisted_artifacts: %w[discovery_evidence discovery_index],
              field_masks: 'credential_and_provider_text_sanitized',
              streaming: 'not_applicable'
            ),
            agent_status: 'implemented',
            application_command: 'SloRulesEngine::Application::DiscoverTelemetry'
          )
        end
        private_class_method :discover

        def common_arguments
          {
            provider: CommandContract.argument(
              example: 'prometheus_stack',
              schema: CommandSchemas.bounded_string(enum: CommandSchemas::PROVIDERS)
            ),
            base_url: CommandContract.argument(
              example: 'http://localhost:9090',
              schema: CommandSchemas.bounded_string(format: 'uri'),
              required: false
            ),
            allowed_hosts: CommandContract.argument(
              example: ['localhost'],
              schema: { type: 'array', minItems: 1, maxItems: 20, items: HOST_SCHEMA },
              required: false
            ),
            from: CommandContract.argument(
              example: 1_786_000_000,
              schema: TIMESTAMP_SCHEMA,
              required: false,
              include_in_example: false
            ),
            to: CommandContract.argument(
              example: 1_786_000_300,
              schema: TIMESTAMP_SCHEMA,
              required: false,
              include_in_example: false
            ),
            validate_only: CommandContract.argument(
              example: false,
              schema: { type: 'boolean' },
              required: false,
              include_in_example: false
            )
          }
        end
        private_class_method :common_arguments
      end
    end
  end
end
