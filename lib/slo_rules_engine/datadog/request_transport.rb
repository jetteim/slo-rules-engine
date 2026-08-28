# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

module SloRulesEngine
  module Datadog
    class RequestTransport
      TRANSIENT_CODES = %w[429 500 502 503 504].freeze
      SUCCESS_CODES = %w[200 201 202].freeze

      def initialize(
        api_key:,
        app_key:,
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

      def request(method, path, payload: nil, retries: 3, not_found_ok: false, max_response_bytes: nil)
        uri = uri_for(path)
        attempt = 0
        transport_attempt = 0

        loop do
          response = perform(method.to_s.upcase, uri, payload)
          transport_attempt = 0
          body = response.body.to_s
          if max_response_bytes && body.bytesize > max_response_bytes
            raise ApiError.new('Datadog response exceeded the byte limit', response: response)
          end
          return parse_body(body) if SUCCESS_CODES.include?(response.code)
          return nil if not_found_ok && response.code == '404'

          attempt += 1
          raise ApiError.new("Datadog #{method} #{path} failed with #{response.code}: #{body}", response: response) unless transient?(response, attempt, retries)

          @sleep_fn.call(retry_after(response))
        end
      rescue Errno::ECONNRESET
        transport_attempt += 1
        raise if transport_attempt > retries

        @sleep_fn.call(transport_retry_delay(transport_attempt))
        retry
      end

      private

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
    end
  end
end
