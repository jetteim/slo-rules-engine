# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

module SloRulesEngine
  module Datadog
    class MissingCredentials < StandardError; end
    class ApiError < StandardError; end

    class Client
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

        raise MissingCredentials, 'DD_API_KEY and DD_APP_KEY are required for live Datadog apply'
      end

      def existing_state
        { slos: {}, monitors: {}, dashboards: {} }
      end

      def request(method, path, payload: nil, retries: 3)
        validate_credentials!
        uri = uri_for(path)
        attempt = 0

        loop do
          attempt += 1
          response = perform(method.to_s.upcase, uri, payload)
          return parse_body(response.body) if SUCCESS_CODES.include?(response.code)

          raise ApiError, "Datadog #{method} #{path} failed with #{response.code}: #{response.body}" unless transient?(response, attempt, retries)

          @sleep_fn.call(retry_after(response))
        end
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
        retry_after = response['Retry-After'].to_i
        rate_limit_reset = response['X-RateLimit-Reset'].to_i
        [retry_after, rate_limit_reset, 1].max
      end

      def parse_body(body)
        return {} if body.to_s.empty?

        JSON.parse(body)
      end
    end
  end
end
