# frozen_string_literal: true

module SloRulesEngine
  module Appliers
    class Datadog
      DEFAULT_SLO_TIMEFRAME = '30d'
      MANAGED_TAG = 'managed_by:slo-rules-engine'
      BURN_RATE_SHORT_WINDOWS = {
        '1h' => '5m',
        '6h' => '30m',
        '24h' => '120m'
      }.freeze

      ARTIFACTS = [
        {
          collection: :slos,
          state: :slos,
          target: 'datadog.slo',
          source_prefix: 'artifacts.slos',
          create: ['POST', '/api/v1/slo'],
          update: ['PUT', '/api/v1/slo/%<id>s']
        },
        {
          collection: :monitors,
          state: :monitors,
          target: 'datadog.monitor',
          source_prefix: 'artifacts.monitors',
          create: ['POST', '/api/v1/monitor'],
          update: ['PUT', '/api/v1/monitor/%<id>s']
        },
        {
          collection: :telemetry_gap_monitors,
          state: :monitors,
          target: 'datadog.monitor',
          source_prefix: 'artifacts.telemetry_gap_monitors',
          create: ['POST', '/api/v1/monitor'],
          update: ['PUT', '/api/v1/monitor/%<id>s']
        },
        {
          collection: :dashboards,
          state: :dashboards,
          target: 'datadog.dashboard',
          source_prefix: 'artifacts.dashboards',
          create: ['POST', '/api/v1/dashboard'],
          update: ['PUT', '/api/v1/dashboard/%<id>s']
        }
      ].freeze

      def initialize(client: SloRulesEngine::Datadog::Client.new)
        @client = client
      end

      def plan(manifest, mode: 'dry_run')
        state = @client.existing_state(desired: desired_state(manifest))
        operations = ARTIFACTS.flat_map do |spec|
          collection(manifest, spec.fetch(:collection)).each_with_index.map do |artifact, index|
            operation_for(manifest, artifact, index, spec, state)
          end
        end

        ApplyPlan.new(provider: 'datadog', mode: mode, operations: operations)
      end

      def diff(manifest)
        state = @client.existing_state(desired: desired_state(manifest))
        resolved_slo_ids = fetch_value(state, :slos, {}).each_with_object({}) do |(name, entry), resolved|
          backend_id = fetch_value(entry, :id)
          resolved[name] = backend_id.to_s if backend_id
        end
        operations = ARTIFACTS.flat_map do |spec|
          collection(manifest, spec.fetch(:collection)).each_with_index.map do |artifact, index|
            diff_operation_for(manifest, artifact, index, spec, state, resolved_slo_ids)
          end
        end

        ApplyPlan.new(provider: 'datadog', mode: 'diff', operations: operations)
      end

      def import(manifest)
        @client.validate_credentials!

        ImportedState.new(
          provider: 'datadog',
          service: manifest.fetch(:service),
          source: 'backend_api',
          state: @client.existing_state(desired: desired_state(manifest))
        )
      end

      def apply(manifest)
        @client.validate_credentials!

        plan(manifest, mode: 'live').tap do |apply_plan|
          resolved_slo_ids = apply_plan.operations.each_with_object({}) do |operation, resolved|
            next unless operation.target == 'datadog.slo' && operation.backend_id

            resolved[operation.name] = operation.backend_id.to_s
          end
          apply_plan.operations.each do |operation|
            method, path = request_target(operation)
            payload = resolve_payload(operation.payload, resolved_slo_ids)
            response = @client.request(method, path, payload: payload)
            next unless operation.target == 'datadog.slo'

            generated_id = datadog_id_from_response(response)
            resolved_slo_ids[operation.name] = generated_id if generated_id
          end
        end
      end

      private

      def operation_for(manifest, artifact, index, spec, state)
        source = "#{spec.fetch(:source_prefix)}[#{index}]"
        name = artifact_name(artifact, spec.fetch(:target), index)
        backend_id = backend_id_for(state, spec.fetch(:state), name)
        action = backend_id ? 'update' : 'create'

        ApplyOperation.new(
          action: action,
          target: spec.fetch(:target),
          name: name,
          source: source,
          payload: payload_for(manifest, artifact, spec.fetch(:target), source),
          backend_id: backend_id
        )
      end

      def collection(manifest, key)
        artifacts = fetch_value(manifest, :artifacts, {})
        fetch_value(artifacts, key, [])
      end

      def artifact_name(artifact, target, index)
        fetch_value(artifact, :name) || fetch_value(artifact, :title) || "#{target} #{index + 1}"
      end

      def backend_id_for(state, bucket, name)
        existing = fetch_value(fetch_value(state, bucket, {}), name)
        return unless existing
        return fetch_value(existing, :id) if existing.respond_to?(:fetch)

        existing
      end

      def payload_for(manifest, artifact, target, source)
        case target
        when 'datadog.slo'
          slo_payload(manifest, artifact, source)
        when 'datadog.monitor'
          monitor_payload(manifest, artifact, source)
        when 'datadog.dashboard'
          dashboard_payload(manifest, artifact, source)
        else
          raise SloRulesEngine::UnsupportedApplyAction, "unsupported Datadog target #{target.inspect}"
        end
      end

      def diff_operation_for(manifest, artifact, index, spec, state, resolved_slo_ids)
        source = "#{spec.fetch(:source_prefix)}[#{index}]"
        name = artifact_name(artifact, spec.fetch(:target), index)
        backend_state = fetch_value(fetch_value(state, spec.fetch(:state), {}), name)
        backend_id = fetch_value(backend_state, :id)
        desired_payload = comparable_payload(
          spec.fetch(:target),
          resolve_payload(payload_for(manifest, artifact, spec.fetch(:target), source), resolved_slo_ids)
        )
        actual_payload = comparable_payload(spec.fetch(:target), fetch_value(backend_state, :payload))
        changes = if backend_state.nil?
                    ['payload']
                  elsif actual_payload.nil?
                    ['payload']
                  else
                    SloRulesEngine::StateDiff.changed_paths(desired_payload, actual_payload)
                  end
        action = if backend_state.nil?
                   'create'
                 elsif changes.empty?
                   'noop'
                 else
                   'update'
                 end

        ApplyOperation.new(
          action: action,
          target: spec.fetch(:target),
          name: name,
          source: source,
          payload: desired_payload,
          backend_id: backend_id,
          actual: actual_payload,
          changes: changes
        )
      end

      def request_target(operation)
        spec = ARTIFACTS.find { |candidate| candidate.fetch(:target) == operation.target }
        endpoint = operation.action == 'update' ? spec.fetch(:update) : spec.fetch(:create)
        method = endpoint.fetch(0)
        path_template = endpoint.fetch(1)
        [method, format(path_template, id: operation.backend_id)]
      end

      def desired_state(manifest)
        artifacts = fetch_value(manifest, :artifacts, {})
        {
          slos: collection(manifest, :slos).map { |artifact| artifact_name(artifact, 'datadog.slo', 0) },
          monitors: collection(manifest, :monitors).each_with_index.map { |artifact, index| artifact_name(artifact, 'datadog.monitor', index) } +
            collection(manifest, :telemetry_gap_monitors).each_with_index.map { |artifact, index| artifact_name(artifact, 'datadog.monitor', index) },
          dashboards: collection(manifest, :dashboards).map { |artifact| fetch_value(artifact, :title) }.compact
        }
      end

      def slo_payload(manifest, artifact, source)
        query = fetch_value(artifact, :query, {})
        success_selector = fetch_value(query, :success_selector, {})
        if success_selector.nil? || success_selector.empty?
          raise SloRulesEngine::UnsupportedApplyAction,
                "Datadog metric SLO apply requires a success_selector for #{fetch_value(artifact, :name).inspect}"
        end

        {
          name: fetch_value(artifact, :name),
          type: 'metric',
          description: generated_description(manifest, artifact, source),
          query: {
            numerator: metric_count_query(query_scope(query, include_success: true), fetch_value(query, :metric)),
            denominator: metric_count_query(query_scope(query, include_success: false), fetch_value(query, :metric))
          },
          tags: datadog_tags(manifest, artifact),
          thresholds: [
            {
              timeframe: DEFAULT_SLO_TIMEFRAME,
              target: objective_percent(fetch_value(artifact, :objective_ratio))
            }
          ],
          timeframe: DEFAULT_SLO_TIMEFRAME,
          target_threshold: objective_percent(fetch_value(artifact, :objective_ratio))
        }
      end

      def monitor_payload(manifest, artifact, source)
        case fetch_value(artifact, :type)
        when 'burn_rate'
          burn_rate_monitor_payload(manifest, artifact, source)
        when 'missing_telemetry'
          telemetry_gap_monitor_payload(manifest, artifact, source)
        else
          raise SloRulesEngine::UnsupportedApplyAction,
                "Unsupported Datadog monitor type #{fetch_value(artifact, :type).inspect}"
        end
      end

      def burn_rate_monitor_payload(manifest, artifact, source)
        primary_window = Array(fetch_value(artifact, :burn_rate_windows, [])).fetch(0)
        long_window = fetch_value(primary_window, :range)
        short_window = BURN_RATE_SHORT_WINDOWS.fetch(long_window, '5m')
        threshold = fetch_value(primary_window, :threshold)

        {
          name: fetch_value(artifact, :name),
          type: 'slo alert',
          query: %(burn_rate("__SLO_REF__[#{slo_reference_name_from_context(artifact)}]").over("#{DEFAULT_SLO_TIMEFRAME}").long_window("#{long_window}").short_window("#{short_window}") > #{threshold}),
          message: burn_rate_message(artifact),
          tags: datadog_tags(manifest, artifact).push("route_key:#{fetch_value(artifact, :route_key)}"),
          options: {
            include_tags: true,
            thresholds: {
              critical: threshold
            }
          }
        }
      end

      def telemetry_gap_monitor_payload(manifest, artifact, source)
        query = fetch_value(artifact, :query, {})

        {
          name: fetch_value(artifact, :name),
          type: 'query alert',
          query: "avg(last_10m):#{metric_count_query(query_scope(query, include_success: false), fetch_value(query, :metric))} < 0",
          message: telemetry_gap_message(artifact),
          tags: datadog_tags(manifest, artifact).push("route_key:#{fetch_value(artifact, :route_key)}"),
          options: {
            include_tags: true,
            notify_no_data: true,
            no_data_timeframe: 10,
            thresholds: {
              critical: 0
            }
          }
        }
      end

      def dashboard_payload(manifest, artifact, source)
        query = first_slo_query(manifest)

        {
          title: fetch_value(artifact, :title),
          description: "Generated dashboard for #{fetch_value(manifest, :service)} from #{source}",
          layout_type: 'ordered',
          template_variables: fetch_value(artifact, :variables, {}).map do |name, default|
            {
              name: name.to_s,
              prefix: name.to_s,
              default: default.to_s
            }
          end,
          widgets: [
            {
              definition: {
                type: 'note',
                content: dashboard_summary(artifact),
                background_color: 'white'
              }
            },
            {
              definition: {
                type: 'timeseries',
                title: 'SLI evidence',
                requests: [
                  {
                    q: dashboard_query_expression(query)
                  }
                ]
              }
            }
          ]
        }
      end

      def query_scope(query, include_success:)
        parse_scope(fetch_value(query, :query))
          .merge(fetch_value(query, :selector, {}))
          .merge(include_success ? fetch_value(query, :success_selector, {}) : {})
      end

      def parse_scope(expression)
        match = expression.to_s.match(/\{([^}]*)\}/)
        return {} unless match

        match[1].split(',').each_with_object({}) do |part, scope|
          key, value = part.split(':', 2)
          next if key.to_s.empty? || value.to_s.empty?

          scope[key] = value
        end
      end

      def metric_count_query(scope, metric)
        tags = scope.sort_by { |key, _value| key.to_s }.map { |key, value| "#{key}:#{value}" }
        %(count:#{metric}{#{tags.empty? ? '*' : tags.join(',')}}.as_count())
      end

      def datadog_tags(manifest, artifact)
        [
          MANAGED_TAG,
          "service:#{fetch_value(manifest, :service)}",
          "owner:#{fetch_value(artifact, :owner)}",
          "sli:#{fetch_value(artifact, :sli)}",
          "sli_instance:#{fetch_value(artifact, :sli_instance)}",
          "slo:#{fetch_value(artifact, :slo)}"
        ].compact
      end

      def generated_description(manifest, artifact, source)
        "Generated by slo-rules-engine for #{fetch_value(manifest, :service)} from #{source}"
      end

      def objective_percent(value)
        (value.to_f * 100).round(3)
      end

      def slo_reference_name_from_context(artifact)
        context = fetch_value(artifact, :message_context, {})
        [
          fetch_value(context, :service),
          fetch_value(context, :sli),
          fetch_value(context, :sli_instance),
          fetch_value(context, :slo)
        ].join(' ')
      end

      def burn_rate_message(artifact)
        context = fetch_value(artifact, :message_context, {})
        secondary = Array(fetch_value(artifact, :burn_rate_windows, []))[1..]&.map do |window|
          "#{fetch_value(window, :threshold)} over #{fetch_value(window, :range)}"
        end
        [
          "SLO burn rate alert for #{fetch_value(context, :service)} #{fetch_value(context, :sli)} #{fetch_value(context, :slo)}.",
          ("Secondary review windows: #{secondary.join(', ')}." if secondary && !secondary.empty?),
          ("Playbook: #{fetch_value(context, :playbook_url)}" if fetch_value(context, :playbook_url)),
          ("Dashboard: #{fetch_value(context, :dashboard_path)}" if fetch_value(context, :dashboard_path))
        ].compact.join("\n")
      end

      def telemetry_gap_message(artifact)
        context = fetch_value(artifact, :message_context, {})
        [
          "Telemetry gap detected for #{fetch_value(context, :service)} #{fetch_value(context, :sli)}.",
          fetch_value(context, :impact),
          ("Playbook: #{fetch_value(context, :playbook_url)}" if fetch_value(context, :playbook_url)),
          ("Dashboard: #{fetch_value(context, :dashboard_path)}" if fetch_value(context, :dashboard_path))
        ].compact.join("\n")
      end

      def dashboard_summary(artifact)
        variables = fetch_value(artifact, :variables, {}).map { |key, value| "- #{key}: #{value}" }
        ([fetch_value(artifact, :source).to_s] + variables).join("\n")
      end

      def first_slo_query(manifest)
        slo = collection(manifest, :slos).fetch(0, {})
        fetch_value(slo, :query, {})
      end

      def dashboard_query_expression(query)
        fetch_value(query, :query) || metric_count_query(query_scope(query, include_success: false), fetch_value(query, :metric))
      end

      def resolve_payload(payload, resolved_slo_ids)
        case payload
        when Array
          payload.map { |item| resolve_payload(item, resolved_slo_ids) }
        when Hash
          payload.each_with_object({}) do |(key, value), resolved|
            resolved[key] = resolve_payload(value, resolved_slo_ids)
          end
        when String
          payload.gsub(/__SLO_REF__\[(.*?)\]/) do
            resolved_slo_ids.fetch(Regexp.last_match(1), Regexp.last_match(0))
          end
        else
          payload
        end
      end

      def datadog_id_from_response(response)
        fetch_value(fetch_value(response, :data, []).fetch(0, {}), :id) ||
          fetch_value(fetch_value(response, :data, {}), :id) ||
          fetch_value(response, :id)
      end

      def comparable_payload(target, payload)
        case target
        when 'datadog.slo'
          normalize_hash(payload) do |hash|
            hash[:tags] = Array(fetch_value(hash, :tags, [])).map(&:to_s).sort
            hash[:thresholds] = Array(fetch_value(hash, :thresholds, [])).map do |entry|
              normalize_hash(entry)
            end
          end
        when 'datadog.monitor'
          normalize_hash(payload) do |hash|
            hash[:tags] = Array(fetch_value(hash, :tags, [])).map(&:to_s).sort
            options = normalize_hash(fetch_value(hash, :options, {}))
            thresholds = normalize_hash(fetch_value(options, :thresholds, {}))
            options[:thresholds] = thresholds
            hash[:options] = options
          end
        when 'datadog.dashboard'
          normalize_hash(payload) do |hash|
            hash[:template_variables] = Array(fetch_value(hash, :template_variables, [])).map do |entry|
              normalize_hash(entry)
            end.sort_by { |entry| fetch_value(entry, :name).to_s }
            hash[:widgets] = Array(fetch_value(hash, :widgets, [])).map do |entry|
              normalize_hash(entry)
            end
          end
        else
          normalize_hash(payload)
        end
      end

      def normalize_hash(value, &block)
        case value
        when Hash
          normalized = value.each_with_object({}) do |(key, entry), hash|
            hash[key.to_sym] = normalize_hash(entry)
          end
          block.call(normalized) if block
          normalized
        when Array
          value.map { |entry| normalize_hash(entry) }
        else
          value
        end
      end

      def fetch_value(hash, key, default = nil)
        return hash.public_send(key) if hash.respond_to?(key)
        return default unless hash.respond_to?(:fetch)

        hash.fetch(key) { hash.fetch(key.to_s, default) }
      end
    end
  end
end
