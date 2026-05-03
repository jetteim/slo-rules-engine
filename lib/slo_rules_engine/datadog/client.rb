# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

module SloRulesEngine
  module Datadog
    class MissingCredentials < StandardError; end
    class ApiError < StandardError
      attr_reader :response

      def initialize(message, response: nil)
        @response = response
        super(message)
      end
    end

    class Client
      MANAGED_MONITOR_TAG = 'managed_by:slo-rules-engine'
      TRANSIENT_CODES = %w[429 500 502 503 504].freeze
      SUCCESS_CODES = %w[200 201 202].freeze

      def initialize(
        api_key: ENV['DD_API_KEY'],
        app_key: ENV['DD_APP_KEY'],
        site: ENV.fetch('DD_SITE', 'datadoghq.com'),
        http: Net::HTTP,
        sleep_fn: ->(seconds) { sleep(seconds) }
      )
        @api_key = api_key
        @app_key = app_key
        @base_uri = URI("https://api.#{site}")
        @http = http
        @sleep_fn = sleep_fn
      end

      def validate_credentials!
        return unless @api_key.to_s.empty? || @app_key.to_s.empty?

        raise MissingCredentials, 'DD_API_KEY and DD_APP_KEY are required for Datadog API calls'
      end

      def existing_state(desired: {})
        return empty_state unless credentials_present?

        {
          slos: load_slos(Array(fetch_value(desired, :slos, []))),
          monitors: load_monitors(Array(fetch_value(desired, :monitors, []))),
          dashboards: load_dashboards(Array(fetch_value(desired, :dashboards, [])))
        }
      end

      def request(method, path, payload: nil, retries: 3, not_found_ok: false)
        validate_credentials!
        uri = uri_for(path)
        attempt = 0
        transport_attempt = 0

        loop do
          response = perform(method.to_s.upcase, uri, payload)
          transport_attempt = 0
          return parse_body(response.body) if SUCCESS_CODES.include?(response.code)
          return nil if not_found_ok && response.code == '404'

          attempt += 1
          raise ApiError.new("Datadog #{method} #{path} failed with #{response.code}: #{response.body}", response: response) unless transient?(response, attempt, retries)

          @sleep_fn.call(retry_after(response))
        end
      rescue Errno::ECONNRESET
        transport_attempt += 1
        raise if transport_attempt > retries

        @sleep_fn.call(transport_retry_delay(transport_attempt))
        retry
      end

      def delete_slo(id, force: false)
        query = force ? '?force=true' : ''
        request('DELETE', "/api/v1/slo/#{id}#{query}", not_found_ok: true)
      end

      def delete_monitor(id)
        request('DELETE', "/api/v1/monitor/#{id}", not_found_ok: true)
      end

      def delete_dashboard(id)
        request('DELETE', "/api/v1/dashboard/#{id}", not_found_ok: true)
      end

      private

      def credentials_present?
        !@api_key.to_s.empty? && !@app_key.to_s.empty?
      end

      def empty_state
        { slos: {}, monitors: {}, dashboards: {} }
      end

      def load_slos(names)
        names.each_with_object({}) do |name, slos|
          path = "/api/v1/slo/search?#{URI.encode_www_form('page[number]' => 0, 'page[size]' => 20, query: name)}"
          response = request('GET', path)
          entries = Array(response.dig('data', 'attributes', 'slos'))
          match = entries.find do |entry|
            fetch_value(fetch_value(entry, :data, {}), :attributes, {}).fetch('name', nil) == name
          end
          next unless match

          data = fetch_value(match, :data, {})
          detail = request('GET', "/api/v1/slo/#{fetch_value(data, :id)}?with_configured_alert_ids=true")
          payload = normalize_slo_payload(first_resource(detail))
          slos[name] = {
            id: fetch_value(data, :id),
            name: fetch_value(fetch_value(data, :attributes, {}), :name),
            payload: payload
          }.compact
        end
      end

      def load_monitors(names)
        names.each_with_object({}) do |name, monitors|
          path = "/api/v1/monitor?#{URI.encode_www_form(monitor_tags: MANAGED_MONITOR_TAG, name: name)}"
          entries = Array(request('GET', path))
          match = entries.find { |entry| fetch_value(entry, :name) == name }
          next unless match

          detail = request('GET', "/api/v1/monitor/#{fetch_value(match, :id)}")
          monitors[name] = {
            id: fetch_value(match, :id),
            name: fetch_value(match, :name),
            payload: normalize_monitor_payload(detail)
          }.compact
        end
      end

      def load_dashboards(titles)
        return {} if titles.empty?

        dashboards = {}
        lists = Array(fetch_value(request('GET', '/api/v1/dashboard/lists/manual'), :dashboard_lists, []))
        lists.each do |list|
          list_id = fetch_value(list, :id)
          next unless list_id

          path = "/api/v1/dashboard/lists/manual/#{list_id}/dashboards"
          entries = Array(fetch_value(request('GET', path), :dashboards, []))
          entries.each do |entry|
            title = fetch_value(entry, :title)
            next unless titles.include?(title)

            detail = request('GET', "/api/v1/dashboard/#{fetch_value(entry, :id)}")
            dashboards[title] ||= {
              id: fetch_value(entry, :id),
              title: title,
              payload: normalize_dashboard_payload(detail)
            }.compact
          end
        end
        dashboards
      end

      def uri_for(path)
        path_uri = URI(path)
        @base_uri.dup.tap do |uri|
          uri.path = path_uri.path
          uri.query = path_uri.query
        end
      end

      def perform(method, uri, payload)
        request_class = {
          'DELETE' => Net::HTTP::Delete,
          'GET' => Net::HTTP::Get,
          'POST' => Net::HTTP::Post,
          'PUT' => Net::HTTP::Put
        }.fetch(method)
        request = request_class.new(uri.request_uri, headers)
        request.body = JSON.generate(payload) if payload
        @http.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |connection|
          connection.request(request)
        end
      end

      def headers
        {
          'Accept' => 'application/json',
          'Content-Type' => 'application/json',
          'DD-API-KEY' => @api_key,
          'DD-APPLICATION-KEY' => @app_key
        }
      end

      def transient?(response, attempt, retries)
        TRANSIENT_CODES.include?(response.code) && attempt <= retries
      end

      def retry_after(response)
        return 60 if %w[500 502 503 504].include?(response.code)

        retry_after = response['Retry-After'].to_i
        rate_limit_reset = response['X-RateLimit-Reset'].to_i
        rate_limit_period = response['X-RateLimit-Period'].to_i
        [retry_after, rate_limit_reset, rate_limit_period, 1].max
      end

      def transport_retry_delay(attempt)
        (2**attempt) / 1000.0
      end

      def parse_body(body)
        return {} if body.to_s.empty?

        JSON.parse(body)
      end

      def first_resource(response)
        data = fetch_value(response, :data, response)
        return data.fetch(0, {}) if data.is_a?(Array)

        data
      end

      def normalize_slo_payload(payload)
        normalize_hash(payload).tap do |normalized|
          normalized[:tags] = Array(fetch_value(normalized, :tags, [])).map(&:to_s).sort
          normalized[:thresholds] = Array(fetch_value(normalized, :thresholds, [])).map { |entry| normalize_hash(entry) }
        end
      end

      def normalize_monitor_payload(payload)
        normalize_hash(payload).tap do |normalized|
          normalized[:tags] = Array(fetch_value(normalized, :tags, [])).map(&:to_s).sort
          options = normalize_hash(fetch_value(normalized, :options, {}))
          options[:thresholds] = normalize_hash(fetch_value(options, :thresholds, {}))
          normalized[:options] = options
        end
      end

      def normalize_dashboard_payload(payload)
        normalize_hash(payload).tap do |normalized|
          normalized[:template_variables] = Array(fetch_value(normalized, :template_variables, [])).map do |entry|
            normalize_hash(entry)
          end.sort_by { |entry| fetch_value(entry, :name).to_s }
          normalized[:widgets] = Array(fetch_value(normalized, :widgets, [])).map { |entry| normalize_hash(entry) }
        end
      end

      def normalize_hash(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, entry), hash|
            hash[key.to_sym] = normalize_hash(entry)
          end
        when Array
          value.map { |entry| normalize_hash(entry) }
        else
          value
        end
      end

      def fetch_value(hash, key, default = nil)
        return hash.public_send(key) if hash.respond_to?(key)
        return default unless hash.respond_to?(:fetch)

        hash.fetch(key) { hash.fetch(key.to_s, default) }
      end
    end
  end
end
