# frozen_string_literal: true

require 'digest'

module SloRulesEngine
  module Application
    class TelemetryAdapterFactory
      def build(provider:, base_url:, from:, to:)
        case provider
        when 'datadog'
          SloRulesEngine::TelemetryLookup::Datadog.new(from: from, to: to)
        when 'prometheus_stack', 'sloth'
          client = if base_url
                     SloRulesEngine::TelemetryLookup::Prometheus::Client.new(base_url: base_url)
                   else
                     SloRulesEngine::TelemetryLookup::Prometheus::Client.new
                   end
          SloRulesEngine::TelemetryLookup::Prometheus.new(client: client, provider: provider)
        else
          raise CommandError.new(
            'unsupported_telemetry_provider',
            'telemetry provider is not supported',
            provider: provider
          )
        end
      end
    end

    class BoundedTelemetryResult
      SafeResult = Struct.new(:payload) do
        def to_h
          payload
        end
      end

      def initialize(resource_policy:, provider:, limit:)
        @resource_policy = resource_policy
        @provider = provider
        @limit = limit
      end

      def normalize(result)
        signals = Array(result.signals)
        valid, invalid = signals.partition do |signal|
          @resource_policy.valid_metric?(signal.metric, provider: @provider)
        end
        returned = @limit ? valid.first(@limit) : valid
        findings = Array(result.findings).map(&:to_h)
        unless invalid.empty?
          findings << {
            code: 'invalid_provider_metrics_omitted',
            message: 'Provider metric identifiers outside the safe contract were omitted.',
            provider: @provider,
            details: {
              count: invalid.length,
              fingerprints: invalid.first(10).map { |signal| fingerprint(signal.metric) }
            }
          }
        end
        if @limit && valid.length > @limit
          findings << {
            code: 'telemetry_results_truncated',
            message: 'Telemetry results exceeded the configured output limit.',
            provider: @provider,
            details: { available: valid.length, returned: returned.length, limit: @limit }
          }
        end

        payload = {
          provider: result.provider,
          signals: returned.map(&:to_h),
          findings: findings
        }
        truncation = {
          truncated: @limit ? valid.length > @limit : false,
          returned: returned.length,
          limit: @limit,
          cursor: nil
        }
        [payload, truncation]
      end

      def wrap(result)
        payload, = normalize(result)
        SafeResult.new(payload)
      end

      private

      def fingerprint(value)
        "sha256:#{Digest::SHA256.hexdigest(value.to_s)}"
      end
    end

    module TelemetryCommandSupport
      PROVIDERS = %w[datadog prometheus_stack sloth].freeze
      DEFAULT_LIMIT = 100
      MAX_LIMIT = 500

      private

      def validate_common!(arguments, context)
        provider = arguments.fetch('provider')
        unless PROVIDERS.include?(provider)
          raise CommandError.new(
            'unsupported_telemetry_provider',
            'telemetry provider is not supported',
            provider: provider
          )
        end

        from = arguments['from']
        to = arguments['to']
        context.resource_policy.validate_window!(from: from, to: to)
        base_url = arguments['base_url']
        allowed_hosts = Array(arguments['allowed_hosts'])
        if provider == 'datadog'
          if base_url || !allowed_hosts.empty?
            raise CommandError.new(
              'unsupported_telemetry_endpoint_override',
              'Datadog telemetry uses its configured site and does not accept base_url or allowed_hosts'
            )
          end
          return [provider, nil, from, to]
        end

        if context.network_policy.confined? && base_url.to_s.empty?
          raise CommandError.new(
            'missing_agent_argument',
            'Prometheus-compatible Agent telemetry requires base_url',
            field: 'base_url'
          )
        end
        normalized_url = if base_url
                           context.network_policy.validate_base_url!(
                             base_url,
                             field: 'base_url',
                             allowed_hosts: allowed_hosts
                           )
                         end
        [provider, normalized_url, from, to]
      end

      def validate_limit!(value, confined:)
        return nil if value.nil? && !confined

        limit = value || DEFAULT_LIMIT
        unless limit.is_a?(Integer) && limit.between?(1, MAX_LIMIT)
          raise CommandError.new(
            'invalid_telemetry_limit',
            "telemetry limit must be between 1 and #{MAX_LIMIT}",
            minimum: 1,
            maximum: MAX_LIMIT
          )
        end
        limit
      end

      def validation_only_result(command_id, provider, arguments)
        CommandResult.new(
          value: {
            valid: true,
            mode: 'validate_only',
            command_id: command_id,
            provider: provider,
            input: {
              batch: !arguments['scope_file'].nil?,
              endpoint_allowlisted: !arguments['base_url'].nil?
            },
            io: {
              local_reads: false,
              local_writes: false,
              provider_calls: false,
              credential_loading: false
            }
          },
          side_effect: 'none'
        )
      end

      def provider_failure(error, provider)
        raise error if error.is_a?(SloRulesEngine::Datadog::MissingCredentials)
        raise error if error.is_a?(InputSafety::Error) || error.is_a?(CommandError)

        raise CommandError.new(
          'telemetry_provider_read_failed',
          'telemetry provider read failed',
          provider: provider,
          error_class: error.class.name
        )
      end
    end

    class LookupTelemetry
      include TelemetryCommandSupport

      def initialize(adapter_factory: nil)
        @adapter_factory = adapter_factory
      end

      def call(arguments, context:)
        provider, base_url, from, to = validate_common!(arguments, context)
        metric = arguments.fetch('metric')
        kind = arguments.fetch('kind', 'unknown')
        query = arguments['query']
        user_visible = arguments.fetch('user_visible', true)
        context.resource_policy.validate_metric!(metric, provider: provider)
        context.resource_policy.validate_kind!(kind)
        context.resource_policy.validate_query!(query)
        return validation_only_result('lookup-telemetry', provider, arguments) if arguments['validate_only'] == true

        adapter_factory = @adapter_factory || context.telemetry_adapter_factory || TelemetryAdapterFactory.new
        result = adapter_factory.build(provider: provider, base_url: base_url, from: from, to: to).lookup(
          metric: metric,
          kind: kind,
          query: query,
          user_visible: user_visible
        )
        payload, truncation = BoundedTelemetryResult.new(
          resource_policy: context.resource_policy,
          provider: provider,
          limit: 1
        ).normalize(result)
        CommandResult.new(value: payload, side_effect: 'provider_read', findings: payload.fetch(:findings), truncation: truncation)
      rescue StandardError => error
        provider_failure(error, arguments['provider'])
      end
    end

    class DiscoverTelemetry
      include TelemetryCommandSupport

      def initialize(adapter_factory: nil)
        @adapter_factory = adapter_factory
      end

      def call(arguments, context:)
        provider, base_url, from, to = validate_common!(arguments, context)
        limit = validate_limit!(arguments['limit'], confined: context.network_policy.confined?)
        scope_file = arguments['scope_file']
        output_dir = arguments['output_dir']
        service = arguments['service']
        selectors = arguments.fetch('selectors', {})
        host = arguments['host']
        validate_mode!(scope_file: scope_file, output_dir: output_dir, service: service, selectors: selectors, host: host)
        validate_paths!(scope_file, output_dir, context)
        context.resource_policy.validate_scope!(
          service: service,
          selectors: selectors,
          host: host,
          provider: provider
        ) unless scope_file
        return validation_only_result('discover-telemetry', provider, arguments) if arguments['validate_only'] == true

        batch = prepare_batch(provider: provider, scope_file: scope_file, output_dir: output_dir, context: context) if scope_file
        adapter_factory = @adapter_factory || context.telemetry_adapter_factory || TelemetryAdapterFactory.new
        adapter = adapter_factory.build(provider: provider, base_url: base_url, from: from, to: to)
        limiter = BoundedTelemetryResult.new(resource_policy: context.resource_policy, provider: provider, limit: limit)
        return run_single(adapter, limiter, service: service, selectors: selectors, host: host) unless scope_file

        run_batch(
          adapter,
          limiter,
          provider: provider,
          scopes: batch.fetch(:scopes),
          resolved_output_dir: batch.fetch(:resolved_output_dir),
          output_dir: output_dir,
          context: context
        )
      rescue StandardError => error
        provider_failure(error, arguments['provider'])
      end

      private

      def validate_mode!(scope_file:, output_dir:, service:, selectors:, host:)
        if scope_file
          unless service.to_s.empty? && selectors.empty? && host.to_s.empty?
            raise CommandError.new(
              'ambiguous_telemetry_scope',
              'scope_file cannot be combined with service, selectors, or host'
            )
          end
          if output_dir.to_s.empty?
            raise CommandError.new('missing_agent_argument', 'batch discovery requires output_dir', field: 'output_dir')
          end
        elsif output_dir
          raise CommandError.new(
            'ambiguous_telemetry_output',
            'output_dir is only supported with scope_file'
          )
        end
      end

      def validate_paths!(scope_file, output_dir, context)
        context.input_policy.validate_lexical_paths!([
          scope_file && { path: scope_file, field: 'scope_file', extensions: ['.json'] },
          output_dir && { path: output_dir, field: 'output_dir', access: :write }
        ])
      end

      def run_single(adapter, limiter, service:, selectors:, host:)
        payload, truncation = limiter.normalize(
          adapter.discover(service: service, selectors: selectors, host: host)
        )
        CommandResult.new(
          value: payload,
          side_effect: 'provider_read',
          findings: payload.fetch(:findings),
          truncation: truncation
        )
      end

      def prepare_batch(provider:, scope_file:, output_dir:, context:)
        resolved_scope_file = context.input_policy.resolve_read_file(
          scope_file,
          field: 'scope_file',
          extensions: ['.json'],
          prevalidated: true
        )
        resolved_output_dir = context.input_policy.resolve_write_root(
          output_dir,
          field: 'output_dir',
          prevalidated: true
        )
        scopes = SloRulesEngine::TelemetryBatchDiscovery.load_scopes(resolved_scope_file, provider: provider)
        scopes.each do |scope|
          context.resource_policy.validate_scope!(
            service: scope.service,
            selectors: scope.selectors,
            host: scope.host,
            provider: provider
          )
        end
        { scopes: scopes, resolved_output_dir: resolved_output_dir }
      end

      def run_batch(adapter, limiter, provider:, scopes:, resolved_output_dir:, output_dir:, context:)
        safe_adapter = Struct.new(:adapter, :limiter) do
          def discover(service:, selectors:, host:)
            limiter.wrap(adapter.discover(service: service, selectors: selectors, host: host))
          end
        end.new(adapter, limiter)
        result = SloRulesEngine::TelemetryBatchDiscovery::Runner.new(
          provider: provider,
          adapter: safe_adapter,
          output_dir: resolved_output_dir,
          path_policy: context.input_policy
        ).run(scopes)
        artifacts = result.fetch(:scopes).filter_map do |entry|
          next unless entry[:result_file]

          { kind: 'discovery_evidence', path: File.join(output_dir, entry.fetch(:result_file)) }
        end
        artifacts << { kind: 'discovery_index', path: File.join(output_dir, 'index.json') }
        CommandResult.new(
          value: result,
          side_effect: 'provider_read',
          findings: result.fetch(:scopes).select { |entry| entry.fetch(:status) == 'error' },
          artifacts: artifacts,
          exit_status: result.fetch(:failed_scopes).zero? ? 0 : 1,
          truncation: {
            truncated: result.fetch(:scopes).any? { |entry| entry[:truncated] == true },
            returned: result.fetch(:scopes).sum { |entry| entry.fetch(:signal_count) },
            limit: limit_for_batch(result),
            cursor: nil
          }
        )
      end

      def limit_for_batch(result)
        result.fetch(:scopes).filter_map { |entry| entry[:limit] }.first
      end
    end
  end
end
