# frozen_string_literal: true

require 'uri'

module SloRulesEngine
  module TelemetryLookup
    class Datadog
      DEFAULT_LOOKBACK_SECONDS = 300

      def initialize(client: SloRulesEngine::Datadog::Client.new, from: nil, to: nil, time_fn: -> { Time.now.to_i })
        @client = client
        @from = from
        @to = to
        @time_fn = time_fn
      end

      def lookup(metric:, kind: 'unknown', user_visible: true, query: nil)
        expression = query || metric
        response = @client.request('GET', query_path(expression))
        series = fetch_value(response, :series, [])

        if series.empty?
          return Result.new(provider: 'datadog', findings: [missing_series(metric)])
        end

        Result.new(
          provider: 'datadog',
          signals: [
            Signal.new(
              kind: kind,
              metric: metric,
              user_visible: user_visible,
              source: 'datadog',
              query: expression,
              series_count: series.length,
              sample_count: datadog_point_count(series),
              rationale: 'Metric has matching Datadog time series in the lookup window.'
            )
          ],
          findings: []
        )
      end

      private

      def query_path(expression)
        params = URI.encode_www_form(from: from_timestamp, query: expression, to: to_timestamp)
        "/api/v1/query?#{params}"
      end

      def from_timestamp
        @from || (to_timestamp - DEFAULT_LOOKBACK_SECONDS)
      end

      def to_timestamp
        @to ||= @time_fn.call.to_i
      end

      def datadog_point_count(series)
        series.sum { |item| Array(fetch_value(item, :pointlist, [])).length }
      end

      def missing_series(metric)
        Finding.new(
          code: 'missing_backend_series',
          provider: 'datadog',
          metric: metric,
          message: 'Datadog query returned no matching time series.'
        )
      end

      def fetch_value(hash, key, default = nil)
        return default unless hash.respond_to?(:fetch)

        hash.fetch(key) { hash.fetch(key.to_s, default) }
      end
    end
  end
end
