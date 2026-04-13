# frozen_string_literal: true

module SloRulesEngine
  BurnRateWindow = Struct.new(
    :percent,
    :range,
    :threshold,
    keyword_init: true
  ) do
    def to_h
      {
        percent: percent,
        range: range,
        threshold: threshold
      }
    end
  end

  class BurnRatePolicy
    DEFAULT_WINDOWS = [
      BurnRateWindow.new(percent: 2, range: '1h', threshold: 14.4),
      BurnRateWindow.new(percent: 5, range: '6h', threshold: 6.0)
    ].freeze

    def initialize(windows: DEFAULT_WINDOWS)
      @windows = windows
    end

    def windows
      @windows.map(&:to_h)
    end
  end
end
