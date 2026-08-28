# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

module SloRulesEngine
  module TelemetryLookup
    class Prometheus
      class Client
        MAX_RESPONSE_BYTES = 2_097_152
        LABEL_NAME = /\A[a-zA-Z_][a-zA-Z0-9_]*\z/

        def initialize(base_url: ENV.fetch('PROMETHEUS_URL', 'http://localhost:9090'), http: Net::HTTP)
          @base_uri = URI(base_url)
          @http = http
        end

        def series(selector)
          response = get('/api/v1/series', [['match[]', selector]])
          response.fetch('data')
        end

        def query(expression)
          get('/api/v1/query', [['query', expression]]).fetch('data')
        end

        def label_values(label_name, matchers: [])
          raise ArgumentError, 'unsafe Prometheus label name' unless label_name.to_s.match?(LABEL_NAME)

          params = matchers.map { |matcher| ['match[]', matcher] }
          encoded_label = URI.encode_www_form_component(label_name).gsub('+', '%20')
          get("/api/v1/label/#{encoded_label}/values", params).fetch('data')
        end

        private

        def get(path, params)
          uri = @base_uri.dup
          uri.path = path
          uri.query = URI.encode_www_form(params)
          response = @http.get_response(uri)
          body = response.body.to_s
          raise 'Prometheus response exceeded the byte limit' if body.bytesize > MAX_RESPONSE_BYTES

          payload = JSON.parse(body)
          raise 'Prometheus provider request failed' unless payload.fetch('status') == 'success'

          payload
        end
      end

      def initialize(client: Client.new, provider: 'prometheus_stack')
        @client = client
        @provider = provider
      end

      def lookup(metric:, kind: 'unknown', user_visible: true, query: nil)
        expression = query || metric
        series = @client.series(metric)
        query_data = series.empty? ? { 'result' => [] } : @client.query(expression)
        samples = fetch_value(query_data, :result, [])

        findings = []
        findings << missing_series(metric) if series.empty?
        findings << missing_query_result(metric) if !series.empty? && samples.empty?

        signals = findings.empty? ? [signal(metric, kind, user_visible, expression, series, samples)] : []
        Result.new(provider: @provider, signals: signals, findings: findings)
      end

      def discover(service: nil, selectors: {}, host: nil)
        raise ArgumentError, 'Prometheus-compatible discovery does not accept host scope' unless host.to_s.empty?

        matcher = matcher_expression(service, selectors)
        metrics = @client.label_values('__name__', matchers: [matcher]).sort

        Result.new(
          provider: @provider,
          signals: metrics.map do |metric|
            TelemetryLookup.discovered_signal(
              metric: metric,
              source: 'prometheus'
            )
          end,
          findings: []
        )
      end

      private

      def signal(metric, kind, user_visible, expression, series, samples)
        Signal.new(
          kind: kind,
          metric: metric,
          user_visible: user_visible,
          source: 'prometheus',
          query: expression,
          series_count: series.length,
          sample_count: samples.length,
          rationale: 'Metric has matching Prometheus-compatible series and query samples.'
        )
      end

      def missing_series(metric)
        Finding.new(
          code: 'missing_backend_series',
          provider: @provider,
          metric: metric,
          message: 'Prometheus-compatible series lookup returned no matching time series.'
        )
      end

      def missing_query_result(metric)
        Finding.new(
          code: 'missing_query_result',
          provider: @provider,
          metric: metric,
          message: 'Prometheus-compatible query returned no samples.'
        )
      end

      def matcher_expression(service, selectors)
        parts = []
        parts << %(service="#{escape_label_value(service)}") unless service.to_s.empty?
        selectors.each do |key, value|
          raise ArgumentError, 'unsafe Prometheus selector key' unless key.to_s.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)

          parts << %(#{key}="#{escape_label_value(value)}")
        end
        "{#{parts.join(',')}}"
      end

      def escape_label_value(value)
        value.to_s.gsub('\\', '\\\\').gsub('"', '\\"').gsub("\n", '\\n')
      end

      def fetch_value(hash, key, default = nil)
        return default unless hash.respond_to?(:fetch)

        hash.fetch(key) { hash.fetch(key.to_s, default) }
      end
    end
  end
end
