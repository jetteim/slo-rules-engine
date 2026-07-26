# frozen_string_literal: true

module SloRulesEngine
  class UnsupportedApplyAction < StandardError; end

  ApplyOperation = Struct.new(
    :action,
    :target,
    :name,
    :source,
    :payload,
    :backend_id,
    :actual,
    :changes,
    :match_identity,
    :risk,
    keyword_init: true
  ) do
    def to_h
      {
        action: action,
        target: target,
        name: name,
        source: source,
        payload: payload,
        backend_id: backend_id,
        actual: actual,
        changes: changes,
        match_identity: match_identity,
        risk: risk
      }.compact
    end
  end

  ApplyPlan = Struct.new(
    :provider,
    :service,
    :mode,
    :operations,
    :desired_state,
    :observed_state,
    :findings,
    keyword_init: true
  ) do
    DESTRUCTIVE_ACTIONS = %w[delete recreate recreate_and_wait].freeze
    RISK_ORDER = %w[low medium high].freeze

    def initialize(**kwargs)
      super
      self.operations ||= []
      self.findings ||= []
    end

    def empty?
      operations.empty?
    end

    def to_h
      payload = {
        provider: provider,
        service: service,
        mode: mode,
        empty: empty?,
        summary: summary,
        operations: operations.map(&:to_h)
      }.compact
      contract = state_contract
      payload[:state_contract] = contract.to_h if contract
      payload
    end

    def summary
      risk_counts = risk_counts_by_level
      {
        total_operations: operations.length,
        actionable_operations: operations.count { |operation| operation.action != 'noop' },
        destructive_operations: operations.count { |operation| DESTRUCTIVE_ACTIONS.include?(operation.action) },
        risky_operations: risk_counts.values.sum,
        highest_risk_level: highest_risk_level(risk_counts),
        operations_by_action: counts_by(&:action),
        operations_by_target: counts_by(&:target),
        operations_by_risk: risk_counts
      }
    end

    private

    def state_contract
      return nil unless desired_state && observed_state

      ProviderState::Plan.new(
        provider: provider,
        service: service,
        mode: mode,
        desired_state: desired_state,
        observed_state: observed_state,
        changes: operations.map { |operation| ProviderState::Change.from_apply_operation(operation) },
        findings: findings.map { |finding| ProviderState::Finding.from_hash(finding, provider: provider) },
        summary: summary
      )
    end

    def counts_by
      operations.each_with_object(Hash.new(0)) do |operation, counts|
        counts[yield(operation)] += 1
      end
    end

    def risk_counts_by_level
      operations.each_with_object(Hash.new(0)) do |operation, counts|
        level = operation.risk&.fetch(:level, nil) || operation.risk&.fetch('level', nil)
        next unless level

        counts[level] += 1
      end
    end

    def highest_risk_level(risk_counts)
      detected = RISK_ORDER.select { |level| risk_counts[level].positive? }
      detected.last || 'none'
    end
  end

  ImportedState = Struct.new(
    :provider,
    :service,
    :mode,
    :source,
    :state,
    :findings,
    :desired_state,
    :observed_state,
    keyword_init: true
  ) do
    def initialize(**kwargs)
      super
      self.mode ||= 'import_existing'
      self.findings ||= []
    end

    def to_h
      payload = {
        provider: provider,
        service: service,
        mode: mode,
        source: source,
        state: state,
        findings: findings
      }
      contract = state_contract
      payload[:state_contract] = contract.to_h if contract
      payload
    end

    private

    def state_contract
      return nil unless desired_state && observed_state

      ProviderState::Import.new(
        provider: provider,
        service: service,
        desired_state: desired_state,
        observed_state: observed_state,
        findings: findings.map { |finding| ProviderState::Finding.from_hash(finding, provider: provider) }
      )
    end
  end

  module StateDiff
    module_function

    def changed_paths(desired, actual, path = nil)
      if desired.is_a?(Hash) && actual.is_a?(Hash)
        keys = (desired.keys.map(&:to_s) + actual.keys.map(&:to_s)).uniq.sort
        return [] if keys.empty? && desired == actual

        return keys.flat_map do |key|
          changed_paths(fetch_key(desired, key), fetch_key(actual, key), join_path(path, key))
        end
      end

      if desired.is_a?(Array) && actual.is_a?(Array)
        return [] if desired == actual

        max = [desired.length, actual.length].max
        return (0...max).flat_map do |index|
          changed_paths(desired[index], actual[index], "#{path}[#{index}]")
        end
      end

      desired == actual ? [] : [path || 'value']
    end

    def fetch_key(hash, key)
      return hash[key] if hash.key?(key)

      symbol_key = key.to_sym
      return hash[symbol_key] if hash.key?(symbol_key)

      nil
    end

    def join_path(path, key)
      return key.to_s if path.to_s.empty?

      "#{path}.#{key}"
    end
  end
end
