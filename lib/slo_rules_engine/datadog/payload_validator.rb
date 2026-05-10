# frozen_string_literal: true

module SloRulesEngine
  module Datadog
    class PayloadError < StandardError
      attr_reader :target, :payload, :result

      def initialize(target:, payload:, result:)
        @target = target
        @payload = payload
        @result = result
        super("Datadog payload for #{target} is invalid")
      end
    end

    module PayloadValidator
      MANAGED_TAG = 'managed_by:slo-rules-engine'

      module_function

      def validate!(target, payload)
        result = validate(target, payload)
        raise PayloadError.new(target: target, payload: payload, result: result) unless result.valid?

        payload
      end

      def validate(target, payload)
        result = SloRulesEngine::ValidationResult.new
        case target
        when 'datadog.slo'
          validate_slo(result, payload)
        when 'datadog.monitor'
          validate_monitor(result, payload)
        when 'datadog.dashboard'
          validate_dashboard(result, payload)
        else
          result.error('target', "unsupported Datadog payload target #{target.inspect}")
        end
        result
      end

      def validate_slo(result, payload)
        type = fetch_value(payload, :type)
        timeframe = fetch_value(payload, :timeframe)
        thresholds = fetch_value(payload, :thresholds)
        target_threshold = fetch_value(payload, :target_threshold)
        validate_presence(result, 'name', fetch_value(payload, :name))
        validate_identity_tags(result, payload, source_prefixes: ['artifacts.slos.'])
        validate_exact(result, 'timeframe', timeframe, '30d')
        validate_array(result, 'thresholds', thresholds)
        validate_numeric(result, 'target_threshold', target_threshold)
        validate_slo_threshold_contract(result, thresholds, timeframe, target_threshold)
        case type
        when 'metric'
          validate_metric_slo(result, payload)
        when 'time_slice'
          validate_time_slice_slo(result, payload)
        else
          result.error('type', 'must equal "metric" or "time_slice"')
        end
      end

      def validate_metric_slo(result, payload)
        query = fetch_value(payload, :query, {})
        validate_hash(result, 'query', query)
        return unless query.is_a?(Hash)

        validate_presence(result, 'query.numerator', fetch_value(query, :numerator))
        validate_presence(result, 'query.denominator', fetch_value(query, :denominator))
      end

      def validate_time_slice_slo(result, payload)
        specification = fetch_value(payload, :sli_specification, {})
        validate_hash(result, 'sli_specification', specification)
        return unless specification.is_a?(Hash)

        time_slice = fetch_value(specification, :time_slice, {})
        validate_hash(result, 'sli_specification.time_slice', time_slice)
        return unless time_slice.is_a?(Hash)

        validate_inclusion(result, 'sli_specification.time_slice.comparator', fetch_value(time_slice, :comparator), %w[< <= > >= ==])
        validate_numeric(result, 'sli_specification.time_slice.query_interval_seconds', fetch_value(time_slice, :query_interval_seconds))
        validate_numeric(result, 'sli_specification.time_slice.threshold', fetch_value(time_slice, :threshold))

        query = fetch_value(time_slice, :query, {})
        validate_hash(result, 'sli_specification.time_slice.query', query)
        return unless query.is_a?(Hash)

        formulas = fetch_value(query, :formulas)
        queries = fetch_value(query, :queries)
        validate_array(result, 'sli_specification.time_slice.query.formulas', formulas)
        validate_array(result, 'sli_specification.time_slice.query.queries', queries)
        Array(formulas).each_with_index do |entry, index|
          validate_hash(result, "sli_specification.time_slice.query.formulas[#{index}]", entry)
          next unless entry.is_a?(Hash)

          validate_presence(result, "sli_specification.time_slice.query.formulas[#{index}].formula", fetch_value(entry, :formula))
        end
        Array(queries).each_with_index do |entry, index|
          validate_hash(result, "sli_specification.time_slice.query.queries[#{index}]", entry)
          next unless entry.is_a?(Hash)

          validate_exact(result, "sli_specification.time_slice.query.queries[#{index}].data_source", fetch_value(entry, :data_source), 'metrics')
          validate_presence(result, "sli_specification.time_slice.query.queries[#{index}].name", fetch_value(entry, :name))
          validate_presence(result, "sli_specification.time_slice.query.queries[#{index}].query", fetch_value(entry, :query))
        end
      end

      def validate_monitor(result, payload)
        validate_presence(result, 'name', fetch_value(payload, :name))
        validate_inclusion(result, 'type', fetch_value(payload, :type), ['slo alert', 'query alert'])
        query = fetch_value(payload, :query)
        validate_presence(result, 'query', query)
        validate_identity_tags(
          result,
          payload,
          source_prefixes: ['artifacts.monitors.', 'artifacts.telemetry_gap_monitors.'],
          route_key_required: true
        )
        if query.to_s.include?('__SLO_REF__[')
          result.error('query', 'contains unresolved SLO reference')
        end
        thresholds = fetch_value(fetch_value(payload, :options, {}), :thresholds, {})
        validate_hash(result, 'options', fetch_value(payload, :options))
        validate_hash(result, 'options.thresholds', thresholds)
        validate_numeric(result, 'options.thresholds.critical', fetch_value(thresholds, :critical))
        return unless fetch_value(payload, :options).is_a?(Hash) && thresholds.is_a?(Hash)

        case fetch_value(payload, :type)
        when 'slo alert'
          validate_burn_rate_monitor_contract(result, payload, thresholds)
        when 'query alert'
          validate_telemetry_gap_monitor_contract(result, payload, thresholds)
        end
      end

      def validate_dashboard(result, payload)
        validate_presence(result, 'title', fetch_value(payload, :title))
        validate_exact(result, 'layout_type', fetch_value(payload, :layout_type), 'ordered')
        validate_identity_tags(result, payload, source_prefixes: ['artifacts.dashboards.'])
        widgets = fetch_value(payload, :widgets)
        validate_array(result, 'widgets', widgets)
        Array(widgets).each_with_index do |widget, index|
          definition = fetch_value(widget, :definition)
          path = "widgets[#{index}].definition"
          validate_hash(result, path, definition)
          next unless definition.is_a?(Hash)

          validate_presence(result, "#{path}.type", fetch_value(definition, :type))
        end
      end

      def validate_identity_tags(result, payload, source_prefixes:, route_key_required: false)
        tags = fetch_value(payload, :tags)
        validate_array(result, 'tags', tags)
        return unless tags.is_a?(Array)

        normalized_tags = tags.map(&:to_s)
        validate_tag_presence(result, normalized_tags, 'tags.managed_by', exact: MANAGED_TAG)
        validate_tag_presence(result, normalized_tags, 'tags.service', prefix: 'service:')
        validate_tag_presence(result, normalized_tags, 'tags.source_ref', prefix: 'source_ref:')
        validate_tag_presence(result, normalized_tags, 'tags.route_key', prefix: 'route_key:') if route_key_required

        source_ref = normalized_tags.find { |tag| tag.start_with?('source_ref:') }
        return unless source_ref

        source_value = source_ref.sub('source_ref:', '')
        return if source_prefixes.any? { |prefix| source_value.start_with?(prefix) }

        result.error('tags.source_ref', "must start with one of #{source_prefixes.inspect}")
      end

      def validate_slo_threshold_contract(result, thresholds, timeframe, target_threshold)
        return unless thresholds.is_a?(Array)
        return if thresholds.empty?

        primary = thresholds.fetch(0)
        unless primary.is_a?(Hash)
          result.error('thresholds[0]', 'must be a hash')
          return
        end

        threshold_timeframe = fetch_value(primary, :timeframe)
        threshold_target = fetch_value(primary, :target)
        validate_exact(result, 'thresholds[0].timeframe', threshold_timeframe, timeframe)
        validate_numeric(result, 'thresholds[0].target', threshold_target)
        return unless threshold_target.is_a?(Numeric) && target_threshold.is_a?(Numeric)

        result.error('target_threshold', 'must match thresholds[0].target') unless threshold_target.to_f == target_threshold.to_f
      end

      def validate_burn_rate_monitor_contract(result, payload, thresholds)
        options = fetch_value(payload, :options, {})
        query = fetch_value(payload, :query).to_s
        validate_exact(result, 'options.include_tags', fetch_value(options, :include_tags), true)
        match = query.match(/\Aburn_rate\("([^"]+)"\)\.over\("30d"\)\.long_window\("([^"]+)"\)\.short_window\("([^"]+)"\) > ([0-9]+(?:\.[0-9]+)?)\z/)
        unless match
          result.error('query', 'must use Datadog burn_rate query shape over "30d"')
          return
        end

        critical = fetch_value(thresholds, :critical)
        return unless critical.is_a?(Numeric)

        query_threshold = match[4].to_f
        result.error('options.thresholds.critical', 'must match query threshold') unless critical.to_f == query_threshold
      end

      def validate_telemetry_gap_monitor_contract(result, payload, thresholds)
        options = fetch_value(payload, :options, {})
        query = fetch_value(payload, :query).to_s
        validate_exact(result, 'options.include_tags', fetch_value(options, :include_tags), true)
        validate_exact(result, 'options.notify_no_data', fetch_value(options, :notify_no_data), true)
        validate_exact(result, 'options.no_data_timeframe', fetch_value(options, :no_data_timeframe), 10)
        result.error('query', 'must use avg(last_10m) no-data query shape ending in < 0') unless query.match?(/\Aavg\(last_10m\):.+ < 0\z/)
        validate_exact(result, 'options.thresholds.critical', fetch_value(thresholds, :critical), 0)
      end

      def validate_tag_presence(result, tags, path, exact: nil, prefix: nil)
        present = if exact
                    tags.include?(exact)
                  else
                    tags.any? { |tag| tag.start_with?(prefix) }
                  end
        result.error(path, 'is required') unless present
      end

      def validate_presence(result, path, value)
        result.error(path, 'is required') if value.nil? || (value.respond_to?(:empty?) && value.empty?)
      end

      def validate_hash(result, path, value)
        result.error(path, 'must be a hash') unless value.is_a?(Hash)
      end

      def validate_array(result, path, value)
        result.error(path, 'must be an array') unless value.is_a?(Array)
      end

      def validate_numeric(result, path, value)
        result.error(path, 'must be numeric') unless value.is_a?(Numeric)
      end

      def validate_exact(result, path, value, expected)
        result.error(path, "must equal #{expected.inspect}") unless value == expected
      end

      def validate_inclusion(result, path, value, allowed)
        result.error(path, "must be one of #{allowed.inspect}") unless allowed.include?(value)
      end

      def fetch_value(hash, key, default = nil)
        return hash.public_send(key) if hash.respond_to?(key)
        return default unless hash.respond_to?(:fetch)

        hash.fetch(key) { hash.fetch(key.to_s, default) }
      end
    end
  end
end
