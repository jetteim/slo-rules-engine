# frozen_string_literal: true

module SloRulesEngine
  module TelemetryLookup
    Signal = Struct.new(
      :kind,
      :metric,
      :user_visible,
      :source,
      :query,
      :series_count,
      :sample_count,
      :observations_per_second,
      :failed_observations_to_alert,
      :rationale,
      keyword_init: true
    ) do
      def to_h
        {
          kind: kind,
          metric: metric,
          user_visible: user_visible,
          source: source,
          query: query,
          series_count: series_count,
          sample_count: sample_count,
          observations_per_second: observations_per_second,
          failed_observations_to_alert: failed_observations_to_alert,
          rationale: rationale
        }.compact
      end
    end

    Finding = Struct.new(
      :code,
      :message,
      :provider,
      :metric,
      :details,
      keyword_init: true
    ) do
      def to_h
        {
          code: code,
          message: message,
          provider: provider,
          metric: metric,
          details: details
        }.compact
      end
    end

    Result = Struct.new(:provider, :signals, :findings, keyword_init: true) do
      def initialize(**kwargs)
        super
        self.signals ||= []
        self.findings ||= []
      end

      def to_h
        {
          provider: provider,
          signals: signals.map(&:to_h),
          findings: findings.map(&:to_h)
        }
      end
    end

    module_function

    def truthy?(value)
      %w[1 true yes y].include?(value.to_s.downcase)
    end

    def extract_signals(payload)
      return [] if payload.nil?
      return payload if payload.is_a?(Array)
      return payload.signals if payload.respond_to?(:signals)
      return payload.fetch(:signals, []) if payload.respond_to?(:fetch) && payload.key?(:signals)
      return payload.fetch('signals', []) if payload.respond_to?(:fetch)

      []
    end

    def classify_metric(metric)
      name = metric.to_s.downcase

      if name.include?('duration') || name.include?('latency')
        {
          kind: 'latency',
          user_visible: true,
          rationale: 'Metric name suggests request latency.'
        }
      elsif name.include?('error') || name.include?('failure')
        {
          kind: 'errors',
          user_visible: true,
          rationale: 'Metric name suggests request errors.'
        }
      elsif name.include?('availability') || name.include?('uptime')
        {
          kind: 'availability',
          user_visible: true,
          rationale: 'Metric name suggests service availability.'
        }
      elsif name.include?('freshness') || name.include?('lag') || name.include?('age')
        {
          kind: 'freshness',
          user_visible: true,
          rationale: 'Metric name suggests data freshness.'
        }
      elsif name.include?('journey') || name.include?('checkout') || name.include?('completion')
        {
          kind: 'user_journey',
          user_visible: true,
          rationale: 'Metric name suggests end-user journey completion.'
        }
      elsif name.include?('heap') || name.include?('memory') || name.include?('cpu') || name.include?('saturation')
        {
          kind: 'saturation',
          user_visible: false,
          rationale: 'Metric name suggests resource saturation rather than user-visible quality.'
        }
      elsif name.include?('request') || name.end_with?('_total') || name.include?('throughput')
        {
          kind: 'traffic',
          user_visible: true,
          rationale: 'Metric name suggests request traffic.'
        }
      else
        {
          kind: 'unknown',
          user_visible: false,
          rationale: 'Metric discovered without a known signal classification; review manually.'
        }
      end
    end

    def discovered_signal(metric:, source:, series_count: nil, sample_count: nil, query: nil)
      classification = classify_metric(metric)
      Signal.new(
        kind: classification.fetch(:kind),
        metric: metric,
        user_visible: classification.fetch(:user_visible),
        source: source,
        query: query,
        series_count: series_count,
        sample_count: sample_count,
        rationale: classification.fetch(:rationale)
      )
    end
  end
end
