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
        query = fetch_value(payload, :query, {})
        validate_presence(result, 'name', fetch_value(payload, :name))
        validate_exact(result, 'type', fetch_value(payload, :type), 'metric')
        validate_hash(result, 'query', query)
        return unless query.is_a?(Hash)

        validate_presence(result, 'query.numerator', fetch_value(query, :numerator))
        validate_presence(result, 'query.denominator', fetch_value(query, :denominator))
      end

      def validate_monitor(result, payload)
        validate_presence(result, 'name', fetch_value(payload, :name))
        validate_inclusion(result, 'type', fetch_value(payload, :type), ['slo alert', 'query alert'])
        query = fetch_value(payload, :query)
        validate_presence(result, 'query', query)
        if query.to_s.include?('__SLO_REF__[')
          result.error('query', 'contains unresolved SLO reference')
        end
        thresholds = fetch_value(fetch_value(payload, :options, {}), :thresholds, {})
        validate_hash(result, 'options', fetch_value(payload, :options))
        validate_hash(result, 'options.thresholds', thresholds)
        validate_numeric(result, 'options.thresholds.critical', fetch_value(thresholds, :critical))
      end

      def validate_dashboard(result, payload)
        validate_presence(result, 'title', fetch_value(payload, :title))
        validate_exact(result, 'layout_type', fetch_value(payload, :layout_type), 'ordered')
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
