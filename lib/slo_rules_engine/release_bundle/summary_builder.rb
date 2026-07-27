# frozen_string_literal: true

module SloRulesEngine
  module ReleaseBundle
    class SummaryBuilder
      DESTRUCTIVE_ACTIONS = %w[delete recreate recreate_and_wait].freeze
      RISK_ORDER = %w[low medium high].freeze

      def build(review:, targets:, artifacts:, findings:)
        plan_artifacts = artifacts.select { |artifact| fetch_value(artifact, :kind) == 'change_plan' }
        execution_artifacts = artifacts.select { |artifact| fetch_value(artifact, :kind) == 'execution_result' }
        plans_by_uid = plan_artifacts.to_h { |artifact| [fetch_value(artifact, :uid), artifact] }
        executions_by_uid = execution_artifacts.to_h { |artifact| [fetch_value(artifact, :uid), artifact] }
        provider_summaries = targets.group_by { |target| fetch_value(target, :provider).to_s }.map do |provider, provider_targets|
          plans = provider_targets.filter_map do |target|
            plans_by_uid[fetch_value(target, :change_plan_artifact_uid)]
          end
          executions = provider_targets.filter_map do |target|
            executions_by_uid[fetch_value(target, :execution_artifact_uid)]
          end
          provider_summary = operation_summary(plans).merge(
            provider: provider,
            target_count: provider_targets.length,
            change_plan_count: plans.length
          )
          unless executions.empty?
            provider_summary[:execution_count] = executions.length
            provider_summary[:executions_by_status] = execution_status_counts(executions)
          end
          provider_summary
        end.sort_by { |summary| summary.fetch(:provider) }

        aggregate = aggregate_summaries(provider_summaries)
        summary = {
          scope_count: Array(fetch_value(review, :scopes)).length,
          provider_target_count: targets.length,
          artifact_count: artifacts.length,
          change_plan_count: plan_artifacts.length,
          total_operations: aggregate.fetch(:total_operations),
          actionable_operations: aggregate.fetch(:actionable_operations),
          destructive_operations: aggregate.fetch(:destructive_operations),
          risky_operations: aggregate.fetch(:risky_operations),
          highest_risk_level: aggregate.fetch(:highest_risk_level),
          provider_summaries: provider_summaries,
          finding_count: findings.length
        }
        unless execution_artifacts.empty?
          summary[:execution_count] = execution_artifacts.length
          summary[:executions_by_status] = execution_status_counts(execution_artifacts)
        end
        summary
      end

      private

      def operation_summary(plans)
        operations = plans.flat_map do |artifact|
          Array(fetch_value(fetch_value(artifact, :content), :operations))
        end
        risk_counts = counts(operations.filter_map { |operation| risk_level(operation) })

        {
          total_operations: operations.length,
          actionable_operations: operations.count { |operation| fetch_value(operation, :action) != 'noop' },
          destructive_operations: operations.count do |operation|
            DESTRUCTIVE_ACTIONS.include?(fetch_value(operation, :action))
          end,
          risky_operations: risk_counts.values.sum,
          highest_risk_level: highest_risk_level(risk_counts),
          operations_by_action: counts(operations.map { |operation| fetch_value(operation, :action) }),
          operations_by_target: counts(operations.map { |operation| fetch_value(operation, :target) }),
          operations_by_risk: risk_counts
        }
      end

      def aggregate_summaries(summaries)
        risk_counts = merge_counts(summaries.map { |summary| summary.fetch(:operations_by_risk) })
        {
          total_operations: summaries.sum { |summary| summary.fetch(:total_operations) },
          actionable_operations: summaries.sum { |summary| summary.fetch(:actionable_operations) },
          destructive_operations: summaries.sum { |summary| summary.fetch(:destructive_operations) },
          risky_operations: summaries.sum { |summary| summary.fetch(:risky_operations) },
          highest_risk_level: highest_risk_level(risk_counts)
        }
      end

      def counts(values)
        values.compact.each_with_object(Hash.new(0)) { |value, result| result[value.to_s] += 1 }
          .sort.to_h
      end

      def execution_status_counts(artifacts)
        counts(artifacts.map do |artifact|
          fetch_value(fetch_value(fetch_value(artifact, :content), :result), :status)
        end)
      end

      def merge_counts(collection)
        collection.each_with_object(Hash.new(0)) do |counts, merged|
          counts.each { |key, value| merged[key.to_s] += value.to_i }
        end.sort.to_h
      end

      def risk_level(operation)
        fetch_value(fetch_value(operation, :risk), :level)
      end

      def highest_risk_level(risk_counts)
        RISK_ORDER.reverse.find { |level| risk_counts.fetch(level, 0).positive? } || 'none'
      end

      def fetch_value(container, key)
        return container[key] if container.is_a?(Hash) && container.key?(key)
        return container[key.to_s] if container.is_a?(Hash) && container.key?(key.to_s)

        nil
      end
    end
  end
end
