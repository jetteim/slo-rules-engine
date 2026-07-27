# frozen_string_literal: true

module SloRulesEngine
  module Datadog
    class PayloadTranslator
      DEFAULT_SLO_TIMEFRAME = '30d'
      MANAGED_TAG = 'managed_by:slo-rules-engine'
      BURN_RATE_SHORT_WINDOWS = {
        '1h' => '5m',
        '6h' => '30m',
        '24h' => '120m'
      }.freeze

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

      def resolve(payload, resolved_slo_ids)
        case payload
        when Array
          payload.map { |item| resolve(item, resolved_slo_ids) }
        when Hash
          payload.each_with_object({}) do |(key, value), resolved|
            resolved[key] = resolve(value, resolved_slo_ids)
          end
        when String
          payload.gsub(/__SLO_REF__\[(.*?)\]/) do
            resolved_slo_ids.fetch(Regexp.last_match(1), Regexp.last_match(0))
          end
        else
          payload
        end
      end

      def comparable(target, payload)
        SloRulesEngine::Datadog::PayloadCanonicalizer.canonicalize(target, payload)
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

      private

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

        timeframe = slo_timeframe(artifact)
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
              timeframe: timeframe,
              target: objective_percent(fetch_value(artifact, :objective_ratio))
            }
          ],
          timeframe: timeframe,
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

        timeframe = slo_timeframe(artifact)
        {
          name: fetch_value(artifact, :name),
          type: 'time_slice',
          description: generated_description(manifest, artifact, source),
          sli_specification: { time_slice: specification },
          tags: datadog_tags(manifest, artifact, source),
          thresholds: [
            {
              timeframe: timeframe,
              target: objective_percent(fetch_value(artifact, :objective_ratio))
            }
          ],
          timeframe: timeframe,
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
        timeframe = matching_slo_timeframe(manifest, artifact)

        {
          name: fetch_value(artifact, :name),
          type: 'slo alert',
          query: %(burn_rate("__SLO_REF__[#{slo_reference_name_from_context(artifact)}]").over("#{timeframe}").long_window("#{long_window}").short_window("#{short_window}") > #{threshold}),
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

      def slo_timeframe(artifact)
        fetch_value(artifact, :evaluation_window, DEFAULT_SLO_TIMEFRAME).to_s
      end

      def matching_slo_timeframe(manifest, artifact)
        reference_name = slo_reference_name_from_context(artifact)
        slo = Array(fetch_value(fetch_value(manifest, :artifacts, {}), :slos, [])).find do |candidate|
          fetch_value(candidate, :name).to_s == reference_name
        end
        slo_timeframe(slo || {})
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

      def generated_description(manifest, _artifact, source)
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
        artifacts = fetch_value(manifest, :artifacts, {})
        fetch_value(artifacts, :slos, []).fetch(0, {})
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

      def fetch_value(hash, key, default = nil)
        return hash.public_send(key) if hash.respond_to?(key)
        return default unless hash.respond_to?(:fetch)

        hash.fetch(key) { hash.fetch(key.to_s, default) }
      end
    end
  end
end
