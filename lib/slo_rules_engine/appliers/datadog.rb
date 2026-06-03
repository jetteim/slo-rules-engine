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
          update: ['PUT', '/api/v1/slo/%<id>s'],
          delete: ['DELETE', '/api/v1/slo/%<id>s']
        },
        {
          collection: :monitors,
          state: :monitors,
          target: 'datadog.monitor',
          source_prefix: 'artifacts.monitors',
          create: ['POST', '/api/v1/monitor'],
          update: ['PUT', '/api/v1/monitor/%<id>s'],
          delete: ['DELETE', '/api/v1/monitor/%<id>s']
        },
        {
          collection: :telemetry_gap_monitors,
          state: :monitors,
          target: 'datadog.monitor',
          source_prefix: 'artifacts.telemetry_gap_monitors',
          create: ['POST', '/api/v1/monitor'],
          update: ['PUT', '/api/v1/monitor/%<id>s'],
          delete: ['DELETE', '/api/v1/monitor/%<id>s']
        },
        {
          collection: :dashboards,
          state: :dashboards,
          target: 'datadog.dashboard',
          source_prefix: 'artifacts.dashboards',
          create: ['POST', '/api/v1/dashboard'],
          update: ['PUT', '/api/v1/dashboard/%<id>s'],
          delete: ['DELETE', '/api/v1/dashboard/%<id>s']
        }
      ].freeze

      PRUNE_ORDER = %i[monitors telemetry_gap_monitors dashboards slos].freeze
      PRUNE_TARGETS = [
        { bucket: :monitors, target: 'datadog.monitor' },
        { bucket: :dashboards, target: 'datadog.dashboard' },
        { bucket: :slos, target: 'datadog.slo' }
      ].freeze

      def initialize(client: SloRulesEngine::Datadog::Client.new, risk_policy: SloRulesEngine::Datadog::RiskPolicy.new)
        @client = client
        @risk_policy = risk_policy
      end

      def plan(manifest, mode: 'dry_run')
        manifest = SloRulesEngine::ManifestSchemaValidator.validate!(manifest)
        state = @client.existing_state(desired: desired_state(manifest))
        resolved_slo_ids = resolved_slo_ids_from_state(state)
        operations = ARTIFACTS.flat_map do |spec|
          collection(manifest, spec.fetch(:collection)).each_with_index.map do |artifact, index|
            plan_operation_for(manifest, artifact, index, spec, state, resolved_slo_ids)
          end
        end

        ApplyPlan.new(provider: 'datadog', mode: mode, operations: operations)
      end

      def diff(manifest)
        manifest = SloRulesEngine::ManifestSchemaValidator.validate!(manifest)
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
        manifest = SloRulesEngine::ManifestSchemaValidator.validate!(manifest)
        @client.validate_credentials!
        state = @client.existing_state(desired: desired_state(manifest))
        managed_state = @client.managed_state(service: manifest.fetch(:service))

        ImportedState.new(
          provider: 'datadog',
          service: manifest.fetch(:service),
          source: 'backend_api',
          state: state,
          findings: missing_backend_resource_findings(manifest, state) +
            orphan_backend_resource_findings(manifest, managed_state) +
            weak_identity_match_findings(state)
        )
      end

      def prune(manifest, mode: 'dry_run')
        manifest = SloRulesEngine::ManifestSchemaValidator.validate!(manifest)
        @client.validate_credentials!
        managed_state = @client.managed_state(service: manifest.fetch(:service))
        operations = prune_operations(manifest, managed_state)

        ApplyPlan.new(provider: 'datadog', mode: mode, operations: operations).tap do |plan|
          next unless mode == 'live'

          preflight_live_ownership!(plan.operations)
          plan.operations.each do |operation|
            prune_operation(operation)
          end
        end
      end

      def apply(manifest)
        manifest = SloRulesEngine::ManifestSchemaValidator.validate!(manifest)
        @client.validate_credentials!

        plan(manifest, mode: 'live').tap do |apply_plan|
          preflight_live_ownership!(apply_plan.operations)
          resolved_slo_ids = apply_plan.operations.each_with_object({}) do |operation, resolved|
            next unless operation.target == 'datadog.slo' && operation.backend_id

            resolved[operation.name] = operation.backend_id.to_s
          end
          apply_plan.operations.each do |operation|
            next if operation.action == 'noop'

            response = apply_operation(operation, resolved_slo_ids)
            next unless operation.target == 'datadog.slo'

            generated_id = operation.backend_id || datadog_id_from_response(response)
            resolved_slo_ids[operation.name] = generated_id if generated_id
          end
        end
      end

      private

      def plan_operation_for(manifest, artifact, index, spec, state, resolved_slo_ids)
        operation = diff_operation_for(manifest, artifact, index, spec, state, resolved_slo_ids)
        if operation.action == 'create' && spec.fetch(:target) == 'datadog.slo'
          operation.action = 'create_and_wait'
        end
        operation
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
                 elsif recreate_monitor?(manifest, artifact, spec, source, name, state, resolved_slo_ids)
                   'recreate'
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
          changes: changes,
          match_identity: fetch_value(backend_state, :match_identity),
          risk: @risk_policy.merge(
            @risk_policy.operation_risk(action: action, target: spec.fetch(:target)),
            @risk_policy.weak_identity_risk(fetch_value(backend_state, :match_identity))
          )
        )
      end

      def request_target(operation)
        spec = ARTIFACTS.find { |candidate| candidate.fetch(:target) == operation.target }
        endpoint = case operation.action
                   when 'create', 'create_and_wait', 'recreate', 'recreate_and_wait'
                     spec.fetch(:create)
                   when 'update'
                     spec.fetch(:update)
                   when 'delete'
                     spec.fetch(:delete)
                   else
                     spec.fetch(:create)
                   end
        method = endpoint.fetch(0)
        path_template = endpoint.fetch(1)
        [method, format(path_template, id: operation.backend_id)]
      end

      def apply_operation(operation, resolved_slo_ids)
        payload = resolve_payload(operation.payload, resolved_slo_ids)
        SloRulesEngine::Datadog::PayloadValidator.validate!(operation.target, payload)

        case operation.action
        when 'create_and_wait'
          create_and_wait(operation, payload)
        when 'recreate'
          recreate(operation, payload)
        when 'recreate_and_wait'
          recreate_and_wait(operation, payload)
        else
          method, path = request_target(operation)
          @client.request(method, path, payload: payload)
        end
      end

      def create_and_wait(operation, payload)
        case operation.target
        when 'datadog.slo'
          @client.create_and_wait_slo(payload)
        when 'datadog.monitor'
          @client.create_and_wait_monitor(payload)
        else
          method, path = request_target(operation)
          @client.request(method, path, payload: payload)
        end
      end

      def recreate(operation, payload)
        case operation.target
        when 'datadog.monitor'
          @client.delete_monitor(operation.backend_id)
          @client.request('POST', '/api/v1/monitor', payload: payload)
        when 'datadog.dashboard'
          @client.delete_dashboard(operation.backend_id)
          @client.request('POST', '/api/v1/dashboard', payload: payload)
        else
          raise SloRulesEngine::UnsupportedApplyAction, "unsupported Datadog recreate target #{operation.target.inspect}"
        end
      end

      def recreate_and_wait(operation, payload)
        case operation.target
        when 'datadog.monitor'
          @client.delete_monitor(operation.backend_id)
          @client.create_and_wait_monitor(payload)
        else
          recreate(operation, payload)
        end
      end

      def resolved_slo_ids_from_state(state)
        fetch_value(state, :slos, {}).each_with_object({}) do |(name, entry), resolved|
          backend_id = fetch_value(entry, :id)
          resolved[name] = backend_id.to_s if backend_id
        end
      end

      def prune_operations(manifest, managed_state)
        desired = desired_state(manifest)
        PRUNE_TARGETS.flat_map do |spec|
          desired_source_counts = Hash.new(0)
          desired_name_counts = Hash.new(0)
          Array(fetch_value(desired, spec.fetch(:bucket), [])).each do |entry|
            source = normalized_source_identity(fetch_value(entry, :source))
            entry_name = fetch_value(entry, :name) || fetch_value(entry, :title)
            desired_source_counts[source] += 1 if source
            desired_name_counts[entry_name] += 1 if entry_name
          end

          Array(fetch_value(managed_state, spec.fetch(:bucket), [])).each_with_index.map do |entry, index|
            entry_name = fetch_value(entry, :name) || fetch_value(entry, :title)
            source = normalized_source_identity(fetch_value(entry, :source))
            if source && desired_source_counts[source].positive?
              desired_source_counts[source] -= 1
              next
            end
            if desired_name_counts[entry_name].positive?
              desired_name_counts[entry_name] -= 1
              next
            end

            match_identity = if source
                               { strategy: 'source_ref', confidence: 'high' }
                             else
                               { strategy: 'service_scope_only', confidence: 'low' }
                             end
            ApplyOperation.new(
              action: 'delete',
              target: spec.fetch(:target),
              name: entry_name,
              source: "managed_state.#{spec.fetch(:bucket)}[#{index}]",
              backend_id: fetch_value(entry, :id),
              match_identity: match_identity,
              risk: @risk_policy.operation_risk(action: 'delete', target: spec.fetch(:target))
            )
          end.compact
        end
      end

      def prune_operation(operation)
        case operation.target
        when 'datadog.slo'
          @client.delete_slo(operation.backend_id, force: true)
        when 'datadog.monitor'
          @client.delete_monitor(operation.backend_id)
        when 'datadog.dashboard'
          @client.delete_dashboard(operation.backend_id)
        else
          raise SloRulesEngine::UnsupportedApplyAction, "unsupported Datadog prune target #{operation.target.inspect}"
        end
      end

      def assert_safe_live_ownership!(operation)
        return unless %w[update recreate recreate_and_wait delete].include?(operation.action)
        return unless weak_match_identity?(operation.match_identity)

        strategy = fetch_value(operation.match_identity, :strategy)
        confidence = fetch_value(operation.match_identity, :confidence)
        result = SloRulesEngine::ValidationResult.new
        result.error(
          'match_identity',
          "live Datadog mutation requires managed source_ref identity for #{operation.action} operations; matched by #{strategy} with #{confidence} confidence"
        )
        raise SloRulesEngine::Datadog::OwnershipError.new(operation: operation, result: result)
      end

      def preflight_live_ownership!(operations)
        operations.each do |operation|
          next if operation.action == 'noop'

          assert_safe_live_ownership!(operation)
        end
      end

      def weak_match_identity?(match_identity)
        return false unless match_identity

        fetch_value(match_identity, :confidence) != 'high'
      end

      def desired_state(manifest)
        {
          slos: collection(manifest, :slos).each_with_index.map do |artifact, index|
            { name: artifact_name(artifact, 'datadog.slo', index), source: "artifacts.slos[#{index}]" }
          end,
          monitors: collection(manifest, :monitors).each_with_index.map do |artifact, index|
            { name: artifact_name(artifact, 'datadog.monitor', index), source: "artifacts.monitors[#{index}]" }
          end + collection(manifest, :telemetry_gap_monitors).each_with_index.map do |artifact, index|
            { name: artifact_name(artifact, 'datadog.monitor', index), source: "artifacts.telemetry_gap_monitors[#{index}]" }
          end,
          dashboards: collection(manifest, :dashboards).each_with_index.map do |artifact, index|
            { title: fetch_value(artifact, :title), source: "artifacts.dashboards[#{index}]" }
          end.compact
        }
      end

      def missing_backend_resource_findings(manifest, state)
        ARTIFACTS.flat_map do |spec|
          collection(manifest, spec.fetch(:collection)).each_with_index.map do |artifact, index|
            name = artifact_name(artifact, spec.fetch(:target), index)
            next if fetch_value(fetch_value(state, spec.fetch(:state), {}), name)

            {
              code: 'missing_backend_resource',
              target: spec.fetch(:target),
              name: name,
              source: "#{spec.fetch(:source_prefix)}[#{index}]",
              message: "managed backend resource #{name.inspect} is missing for #{spec.fetch(:target)}"
            }
          end.compact
        end
      end

      def orphan_backend_resource_findings(manifest, managed_state)
        prune_operations(manifest, managed_state).each_with_index.map do |operation, index|
          {
            code: 'orphan_backend_resource',
            target: operation.target,
            name: operation.name,
            source: operation.source,
            backend_id: operation.backend_id,
            message: "managed backend resource #{operation.name.inspect} is not present in the reviewed manifest"
          }
        end
      end

      def weak_identity_match_findings(state)
        {
          slos: 'datadog.slo',
          monitors: 'datadog.monitor',
          dashboards: 'datadog.dashboard'
        }.flat_map do |bucket, target|
          fetch_value(state, bucket, {}).map do |desired_name, entry|
            match_identity = fetch_value(entry, :match_identity)
            next unless weak_match_identity?(match_identity)

            {
              code: 'weak_identity_match',
              target: target,
              name: desired_name,
              strategy: fetch_value(match_identity, :strategy),
              confidence: fetch_value(match_identity, :confidence),
              message: "backend resource #{desired_name.inspect} matched without managed source_ref identity"
            }
          end.compact
        end
      end

      def slo_payload(manifest, artifact, source)
        if fetch_value(artifact, :calculation_basis) == 'time_slice'
          return time_slice_slo_payload(manifest, artifact, source)
        end

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
          tags: datadog_tags(manifest, artifact, source),
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

      def time_slice_slo_payload(manifest, artifact, source)
        query = fetch_value(artifact, :query, {})
        success_selector = fetch_value(query, :success_selector, {})
        success_threshold = fetch_value(query, :success_threshold, {})
        specification =
          if success_selector && !success_selector.empty?
            counter_ratio_time_slice_specification(artifact, query)
          elsif success_threshold && !success_threshold.empty?
            threshold_time_slice_specification(artifact, query, success_threshold)
          else
            raise SloRulesEngine::UnsupportedApplyAction,
                  "Datadog time-slice apply requires a success_selector or success_threshold for #{fetch_value(artifact, :name).inspect}"
          end

        {
          name: fetch_value(artifact, :name),
          type: 'time_slice',
          description: generated_description(manifest, artifact, source),
          sli_specification: { time_slice: specification },
          tags: datadog_tags(manifest, artifact, source),
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

      def counter_ratio_time_slice_specification(artifact, query)
        if fetch_value(query, :type) != 'counter'
          raise SloRulesEngine::UnsupportedApplyAction,
                "Datadog counter-ratio time-slice apply requires a counter binding for #{fetch_value(artifact, :name).inspect}"
        end

        {
          comparator: '>=',
          query_interval_seconds: query_interval_seconds(fetch_value(query, :range)),
          threshold: fetch_value(artifact, :objective_ratio).to_f,
          query: {
            formulas: [
              { formula: 'success / total' }
            ],
            queries: [
              {
                data_source: 'metrics',
                name: 'total',
                query: metric_sum_query(query_scope(query, include_success: false), fetch_value(query, :metric))
              },
              {
                data_source: 'metrics',
                name: 'success',
                query: metric_sum_query(query_scope(query, include_success: true), fetch_value(query, :metric))
              }
            ]
          }
        }
      end

      def threshold_time_slice_specification(artifact, query, success_threshold)
        {
          comparator: datadog_comparator(fetch_value(success_threshold, :operator)),
          query_interval_seconds: query_interval_seconds(fetch_value(query, :range)),
          threshold: Float(fetch_value(success_threshold, :value)),
          query: {
            formulas: [
              { formula: 'main' }
            ],
            queries: [
              {
                data_source: 'metrics',
                name: 'main',
                query: threshold_time_slice_query_expression(artifact, query, success_threshold)
              }
            ]
          }
        }
      rescue ArgumentError, TypeError
        raise SloRulesEngine::UnsupportedApplyAction,
              "Datadog time-slice threshold must be numeric for #{fetch_value(artifact, :name).inspect}"
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
          tags: datadog_tags(manifest, artifact, source).push("route_key:#{fetch_value(artifact, :route_key)}"),
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
          tags: datadog_tags(manifest, artifact, source).push("route_key:#{fetch_value(artifact, :route_key)}"),
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
        slo_artifact = first_slo_artifact(manifest)

        {
          title: fetch_value(artifact, :title),
          description: "Generated dashboard for #{fetch_value(manifest, :service)} from #{source}",
          tags: datadog_tags(manifest, artifact, source),
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
                    q: dashboard_query_expression(slo_artifact)
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

      def merge_scope_into_query_expression(expression, selector)
        normalized_selector = normalize_scope(selector)
        match = expression.to_s.match(/\A([^{}]+)\{([^}]*)\}(.*)\z/)
        if match
          prefix = match[1]
          existing_scope = parse_scope(expression)
          suffix = match[3]
          merged_scope = existing_scope.merge(normalized_selector)
          tags = merged_scope.sort_by { |key, _value| key.to_s }.map { |key, value| "#{key}:#{value}" }
          return "#{prefix}{#{tags.join(',')}}#{suffix}"
        end

        tags = normalized_selector.sort_by { |key, _value| key.to_s }.map { |key, value| "#{key}:#{value}" }
        return expression.to_s if tags.empty?

        "#{expression}{#{tags.join(',')}}"
      end

      def metric_count_query(scope, metric)
        tags = scope.sort_by { |key, _value| key.to_s }.map { |key, value| "#{key}:#{value}" }
        %(count:#{metric}{#{tags.empty? ? '*' : tags.join(',')}}.as_count())
      end

      def metric_sum_query(scope, metric)
        tags = scope.sort_by { |key, _value| key.to_s }.map { |key, value| "#{key}:#{value}" }
        %(sum:#{metric}{#{tags.empty? ? '*' : tags.join(',')}}.as_count())
      end

      def metric_value_query(scope, metric, aggregation)
        tags = scope.sort_by { |key, _value| key.to_s }.map { |key, value| "#{key}:#{value}" }
        %(#{aggregation}:#{metric}{#{tags.empty? ? '*' : tags.join(',')}})
      end

      def threshold_time_slice_query_expression(artifact, query, success_threshold)
        expression = fetch_value(query, :query)
        return merge_scope_into_query_expression(expression, fetch_value(query, :selector, {})) unless expression.to_s.empty?

        infer_threshold_time_slice_query_expression(artifact, query, success_threshold)
      end

      def infer_threshold_time_slice_query_expression(artifact, query, success_threshold)
        scope = normalize_scope(fetch_value(query, :selector, {}))
        metric = fetch_value(query, :metric)

        case fetch_value(query, :type).to_s
        when 'counter'
          metric_sum_query(scope, metric)
        when 'distribution'
          metric_value_query(scope, metric, "p#{query_objective_percent(fetch_value(artifact, :objective_ratio))}")
        when 'gauge'
          metric_value_query(scope, metric, gauge_aggregation(fetch_value(success_threshold, :operator)))
        else
          raise SloRulesEngine::UnsupportedApplyAction,
                "Datadog threshold-based time-slice apply requires a provider query expression for #{metric.inspect}"
        end
      end

      def datadog_tags(manifest, artifact, source)
        [
          MANAGED_TAG,
          "service:#{fetch_value(manifest, :service)}",
          "owner:#{fetch_value(artifact, :owner)}",
          "sli:#{fetch_value(artifact, :sli)}",
          "sli_instance:#{fetch_value(artifact, :sli_instance)}",
          "slo:#{fetch_value(artifact, :slo)}",
          source_tag(source)
        ].compact
      end

      def source_tag(source)
        return if source.to_s.empty?

        "source_ref:#{normalize_source_ref(source)}"
      end

      def normalize_source_ref(source)
        source.to_s
          .gsub(/\[(\d+)\]/, '.\1')
          .gsub(/[^a-zA-Z0-9_.:-]/, '_')
          .gsub(/\.\.+/, '.')
      end

      def normalized_source_identity(source)
        return if source.to_s.empty?

        normalize_source_ref(source.to_s.sub(/\Asource_ref:/, ''))
      end

      def generated_description(manifest, artifact, source)
        "Generated by slo-rules-engine for #{fetch_value(manifest, :service)} from #{source}"
      end

      def objective_percent(value)
        (value.to_f * 100).round(3)
      end

      def query_objective_percent(value)
        format('%.2f', value.to_f * 100).sub(/\.?0+\z/, '')
      end

      def query_interval_seconds(range)
        match = range.to_s.match(/\A(\d+)([smhd])\z/)
        return 300 unless match

        value = match[1].to_i
        multiplier = case match[2]
                     when 's' then 1
                     when 'm' then 60
                     when 'h' then 3600
                     when 'd' then 86_400
                     else 300
                     end
        value * multiplier
      end

      def datadog_comparator(operator)
        case operator.to_s
        when '<', 'lt' then '<'
        when '<=', 'lte' then '<='
        when '>', 'gt' then '>'
        when '>=', 'gte' then '>='
        when '==', '=', 'eq' then '=='
        else
          raise SloRulesEngine::UnsupportedApplyAction,
                "unsupported Datadog time-slice threshold operator #{operator.inspect}"
        end
      end

      def gauge_aggregation(operator)
        case operator.to_s
        when '<', 'lt', '<=', 'lte' then 'max'
        when '>', 'gt', '>=', 'gte' then 'min'
        when '==', '=', 'eq' then 'avg'
        else
          raise SloRulesEngine::UnsupportedApplyAction,
                "unsupported Datadog gauge threshold operator #{operator.inspect}"
        end
      end

      def normalize_scope(scope)
        return {} unless scope.is_a?(Hash)

        scope.each_with_object({}) do |(key, value), normalized|
          normalized[key.to_s] = value.to_s
        end
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

      def first_slo_artifact(manifest)
        collection(manifest, :slos).fetch(0, {})
      end

      def dashboard_query_expression(artifact)
        query = fetch_value(artifact, :query, {})
        expression = fetch_value(query, :query)
        return merge_scope_into_query_expression(expression, fetch_value(query, :selector, {})) unless expression.to_s.empty?

        success_threshold = fetch_value(query, :success_threshold, {})
        if success_threshold.is_a?(Hash) && !success_threshold.empty?
          return infer_threshold_time_slice_query_expression(artifact, query, success_threshold)
        end

        metric_count_query(query_scope(query, include_success: false), fetch_value(query, :metric))
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
        data = fetch_value(response, :data)
        id = case data
             when Array
               fetch_value(data.fetch(0, {}), :id)
             when Hash
               fetch_value(data, :id)
             end

        id || fetch_value(response, :id)
      end

      def comparable_payload(target, payload)
        SloRulesEngine::Datadog::PayloadCanonicalizer.canonicalize(target, payload)
      end

      def recreate_monitor?(manifest, artifact, spec, source, name, state, resolved_slo_ids)
        return false unless spec.fetch(:target) == 'datadog.monitor'
        return false unless fetch_value(artifact, :type) == 'burn_rate'

        current_slo_id = resolved_slo_ids[slo_reference_name_from_context(artifact)]
        return false if current_slo_id.to_s.empty?

        actual_query = fetch_value(fetch_value(fetch_value(state, :monitors, {}).fetch(name, {}), :payload, {}), :query)
        return false if actual_query.to_s.empty?

        !actual_query.include?(%("#{current_slo_id}"))
      end

      def fetch_value(hash, key, default = nil)
        return hash.public_send(key) if hash.respond_to?(key)
        return default unless hash.respond_to?(:fetch)

        hash.fetch(key) { hash.fetch(key.to_s, default) }
      end
    end
  end
end
