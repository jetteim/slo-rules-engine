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
        changes: changes
      }.compact
    end
  end

  ApplyPlan = Struct.new(:provider, :mode, :operations, keyword_init: true) do
    def initialize(**kwargs)
      super
      self.operations ||= []
    end

    def empty?
      operations.empty?
    end

    def to_h
      {
        provider: provider,
        mode: mode,
        empty: empty?,
        operations: operations.map(&:to_h)
      }
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
