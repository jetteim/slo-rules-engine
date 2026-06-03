# frozen_string_literal: true

module SloRulesEngine
  module Datadog
    class RiskPolicy
      RISK_PRIORITY = {
        'low' => 1,
        'medium' => 2,
        'high' => 3
      }.freeze

      def operation_risk(action:, target:)
        case [action, target]
        when ['recreate', 'datadog.monitor'], ['recreate_and_wait', 'datadog.monitor']
          {
            level: 'high',
            reasons: ['recreate_deletes_existing_monitor', 'alert_coverage_may_drop']
          }
        when ['recreate', 'datadog.dashboard'], ['recreate_and_wait', 'datadog.dashboard']
          {
            level: 'medium',
            reasons: ['recreate_deletes_existing_dashboard']
          }
        when ['delete', 'datadog.monitor']
          {
            level: 'high',
            reasons: ['prune_deletes_managed_monitor', 'alert_coverage_removed']
          }
        when ['delete', 'datadog.slo']
          {
            level: 'high',
            reasons: ['prune_force_deletes_managed_slo', 'slo_coverage_removed']
          }
        when ['delete', 'datadog.dashboard']
          {
            level: 'medium',
            reasons: ['prune_deletes_managed_dashboard']
          }
        end
      end

      def weak_identity_risk(match_identity = nil, strategy: nil, confidence: nil)
        confidence ||= fetch_value(match_identity, :confidence)
        return if confidence.to_s.empty? || confidence == 'high'

        strategy ||= fetch_value(match_identity, :strategy)
        {
          level: 'medium',
          reasons: ['matched_without_source_ref'],
          match_identity: {
            strategy: strategy,
            confidence: confidence
          }.compact
        }
      end

      def merge(*risks)
        present = risks.compact
        return if present.empty?

        {
          level: present.max_by { |risk| RISK_PRIORITY.fetch(fetch_value(risk, :level), 0) }.then { |risk| fetch_value(risk, :level) },
          reasons: present.flat_map { |risk| Array(fetch_value(risk, :reasons, [])) }.uniq
        }
      end

      private

      def fetch_value(hash, key, default = nil)
        return default unless hash.respond_to?(:key?)
        return hash[key] if hash.key?(key)

        string_key = key.to_s
        return hash[string_key] if hash.key?(string_key)

        default
      end
    end
  end
end
