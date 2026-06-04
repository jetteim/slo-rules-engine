# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

module SloRulesEngine
  module Datadog
    class MissingCredentials < StandardError; end
    class OwnershipError < StandardError
      attr_reader :operation, :result

      def initialize(operation:, result:)
        @operation = operation
        @result = result
        super("Datadog live mutation for #{operation.target} #{operation.name.inspect} is unsafe")
      end
    end

    class ApiError < StandardError
      attr_reader :response

      def initialize(message, response: nil)
        @response = response
        super(message)
      end
    end

    class Client
      TRANSIENT_CODES = %w[429 500 502 503 504].freeze
      SUCCESS_CODES = %w[200 201 202].freeze
      WAIT_ATTEMPTS = 20

      def initialize(
        api_key: ENV['DD_API_KEY'],
        app_key: ENV['DD_APP_KEY'],
        site: ENV.fetch('DD_SITE', 'datadoghq.com'),
        http: Net::HTTP,
        sleep_fn: ->(seconds) { sleep(seconds) },
        state_reader: nil
      )
        @api_key = api_key
        @app_key = app_key
        @base_uri = URI("https://api.#{site}")
        @http = http
        @sleep_fn = sleep_fn
        @state_reader = state_reader || SloRulesEngine::Datadog::StateReader.new(requester: self)
      end

      def validate_credentials!
        return unless @api_key.to_s.empty? || @app_key.to_s.empty?

        raise MissingCredentials, 'DD_API_KEY and DD_APP_KEY are required for Datadog API calls'
      end

      def existing_state(desired: {})
        return empty_state unless credentials_present?

        @state_reader.existing_state(desired: desired)
      end

      def managed_state(service:)
        validate_credentials!

        @state_reader.managed_state(service: service)
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

      def create_and_wait_slo(payload)
        response = request('POST', '/api/v1/slo', payload: payload)
        slo_id = fetch_value(fetch_value(response, :data, []).fetch(0, {}), :id) ||
          fetch_value(fetch_value(response, :data, {}), :id)
        wait_for_resource("/api/v1/slo/#{slo_id}") do |result|
          fetch_value(fetch_value(result, :data, {}), :id) == slo_id
        end
        response
      end

      def create_and_wait_monitor(payload)
        response = request('POST', '/api/v1/monitor', payload: payload)
        monitor_id = fetch_value(response, :id)
        wait_for_resource("/api/v1/monitor/#{monitor_id}") do |result|
          fetch_value(result, :id) == monitor_id
        end
        response
      end

      private

      def credentials_present?
        !@api_key.to_s.empty? && !@app_key.to_s.empty?
      end

      def empty_state
        { slos: {}, monitors: {}, dashboards: {} }
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

      def wait_for_resource(path)
        attempts = 1

        loop do
          result = request('GET', path, retries: 0)
          return result if yield(result)
        rescue ApiError
          raise if attempts >= WAIT_ATTEMPTS

          @sleep_fn.call([0.2 * attempts, 2].min)
          attempts += 1
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
