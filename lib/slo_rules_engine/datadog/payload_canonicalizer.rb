# frozen_string_literal: true

module SloRulesEngine
  module Datadog
    module PayloadCanonicalizer
      module_function

      def canonicalize(target, payload)
        normalized = normalize_hash(payload)
        case target
        when 'datadog.slo'
          canonicalize_slo(normalized)
        when 'datadog.monitor'
          canonicalize_monitor(normalized)
        when 'datadog.dashboard'
          canonicalize_dashboard(normalized)
        else
          normalized
        end
      end

      def canonicalize_slo(payload)
        query = fetch_value(payload, :query, {})
        compact_hash(
          name: fetch_value(payload, :name),
          type: fetch_value(payload, :type),
          description: fetch_value(payload, :description),
          query: compact_hash(
            numerator: fetch_value(query, :numerator),
            denominator: fetch_value(query, :denominator)
          ),
          tags: Array(fetch_value(payload, :tags, [])).map(&:to_s).sort,
          thresholds: Array(fetch_value(payload, :thresholds, [])).map do |entry|
            compact_hash(
              timeframe: fetch_value(entry, :timeframe),
              target: fetch_value(entry, :target)
            )
          end,
          timeframe: fetch_value(payload, :timeframe),
          target_threshold: fetch_value(payload, :target_threshold)
        )
      end

      def canonicalize_monitor(payload)
        options = fetch_value(payload, :options, {})
        thresholds = fetch_value(options, :thresholds, {})

        compact_hash(
          name: fetch_value(payload, :name),
          type: fetch_value(payload, :type),
          query: fetch_value(payload, :query),
          message: fetch_value(payload, :message),
          tags: Array(fetch_value(payload, :tags, [])).map(&:to_s).sort,
          options: compact_hash(
            include_tags: fetch_value(options, :include_tags),
            notify_no_data: fetch_value(options, :notify_no_data),
            no_data_timeframe: fetch_value(options, :no_data_timeframe),
            timeout_h: fetch_value(options, :timeout_h),
            require_full_window: fetch_value(options, :require_full_window),
            notification_preset_name: fetch_value(options, :notification_preset_name),
            thresholds: compact_hash(
              critical: fetch_value(thresholds, :critical),
              warning: fetch_value(thresholds, :warning),
              ok: fetch_value(thresholds, :ok),
              unknown: fetch_value(thresholds, :unknown)
            )
          )
        )
      end

      def canonicalize_dashboard(payload)
        compact_hash(
          title: fetch_value(payload, :title),
          description: fetch_value(payload, :description),
          tags: Array(fetch_value(payload, :tags, [])).map(&:to_s).sort,
          layout_type: fetch_value(payload, :layout_type),
          template_variables: Array(fetch_value(payload, :template_variables, [])).map do |entry|
            compact_hash(
              name: fetch_value(entry, :name),
              prefix: fetch_value(entry, :prefix),
              default: fetch_value(entry, :default)
            )
          end.sort_by { |entry| fetch_value(entry, :name).to_s },
          widgets: Array(fetch_value(payload, :widgets, [])).map do |entry|
            { definition: canonicalize_widget_definition(fetch_value(entry, :definition, {})) }
          end
        )
      end

      def canonicalize_widget_definition(definition)
        type = fetch_value(definition, :type)
        case type
        when 'note'
          compact_hash(
            type: type,
            content: fetch_value(definition, :content),
            background_color: fetch_value(definition, :background_color)
          )
        when 'timeseries'
          compact_hash(
            type: type,
            title: fetch_value(definition, :title),
            requests: Array(fetch_value(definition, :requests, [])).map do |request|
              compact_hash(q: fetch_value(request, :q))
            end
          )
        else
          normalize_hash(definition)
        end
      end

      def compact_hash(hash)
        hash.each_with_object({}) do |(key, value), compacted|
          next if value.nil?
          next if value.respond_to?(:empty?) && value.empty?

          compacted[key] = value
        end
      end

      def normalize_hash(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, entry), hash|
            hash[key.to_sym] = normalize_hash(entry)
          end
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
