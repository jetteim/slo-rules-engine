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
  end
end
