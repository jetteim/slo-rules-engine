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
    keyword_init: true
  ) do
    def to_h
      {
        action: action,
        target: target,
        name: name,
        source: source,
        payload: payload,
        backend_id: backend_id
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
end
