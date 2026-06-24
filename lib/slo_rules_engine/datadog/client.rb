# frozen_string_literal: true

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
      WAIT_ATTEMPTS = 20

      def initialize(
        api_key: ENV['DD_API_KEY'],
        app_key: ENV['DD_APP_KEY'],
        site: ENV.fetch('DD_SITE', 'datadoghq.com'),
        http: Net::HTTP,
        sleep_fn: ->(seconds) { sleep(seconds) },
        request_transport: nil,
        state_reader: nil
      )
        @api_key = api_key
        @app_key = app_key
        @sleep_fn = sleep_fn
        @request_transport = request_transport || SloRulesEngine::Datadog::RequestTransport.new(
          api_key: api_key,
          app_key: app_key,
          site: site,
          http: http,
          sleep_fn: sleep_fn
        )
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

        @request_transport.request(method, path, payload: payload, retries: retries, not_found_ok: not_found_ok)
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
