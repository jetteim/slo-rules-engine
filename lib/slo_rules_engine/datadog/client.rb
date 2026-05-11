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
      MANAGED_MONITOR_TAG = 'managed_by:slo-rules-engine'
      TRANSIENT_CODES = %w[429 500 502 503 504].freeze
      SUCCESS_CODES = %w[200 201 202].freeze
      WAIT_ATTEMPTS = 20

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

      def managed_state(service:)
        validate_credentials!

        {
          slos: load_managed_slos(service),
          monitors: load_managed_monitors(service),
          dashboards: load_managed_dashboards(service)
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

      def load_slos(names)
        names.each_with_object({}) do |entry, slos|
          desired_name = desired_name(entry, :name)
          match = find_slo_match(desired_name, desired_source(entry))
          next unless match

          data = fetch_value(match.fetch(:entry), :data, {})
          detail = request('GET', "/api/v1/slo/#{fetch_value(data, :id)}?with_configured_alert_ids=true")
          payload = normalize_slo_payload(first_resource(detail))
          slos[desired_name] = {
            id: fetch_value(data, :id),
            name: fetch_value(fetch_value(data, :attributes, {}), :name),
            payload: payload,
            match_identity: match.fetch(:match_identity)
          }.compact
        end
      end

      def load_monitors(names)
        names.each_with_object({}) do |entry, monitors|
          desired_name = desired_name(entry, :name)
          match = find_monitor_match(desired_name, desired_source(entry))
          next unless match

          detail = request('GET', "/api/v1/monitor/#{fetch_value(match.fetch(:entry), :id)}")
          monitors[desired_name] = {
            id: fetch_value(match.fetch(:entry), :id),
            name: fetch_value(match.fetch(:entry), :name),
            payload: normalize_monitor_payload(detail),
            match_identity: match.fetch(:match_identity)
          }.compact
        end
      end

      def load_dashboards(titles)
        desired_titles = Array(titles).map do |entry|
          {
            title: desired_name(entry, :title),
            source: desired_source(entry)
          }
        end
        return {} if desired_titles.empty?

        desired_by_source = desired_titles.each_with_object({}) do |entry, hash|
          source = entry.fetch(:source)
          hash[normalize_source_ref(source)] = entry.fetch(:title) if source
        end
        desired_by_title = desired_titles.each_with_object({}) do |entry, hash|
          hash[entry.fetch(:title)] = entry.fetch(:title)
        end
        dashboards = {}
        lists = Array(fetch_value(request('GET', '/api/v1/dashboard/lists/manual'), :dashboard_lists, []))
        lists.each do |list|
          list_id = fetch_value(list, :id)
          next unless list_id

          path = "/api/v1/dashboard/lists/manual/#{list_id}/dashboards"
          entries = Array(fetch_value(request('GET', path), :dashboards, []))
          entries.each do |entry|
            title = fetch_value(entry, :title)
            detail = request('GET', "/api/v1/dashboard/#{fetch_value(entry, :id)}")
            source = extract_source_ref(Array(fetch_value(detail, :tags, [])).map(&:to_s))
            desired_title = if source && desired_by_source.key?(source)
                              desired_by_source.fetch(source)
                            else
                              desired_by_title[title]
                            end
            next unless desired_title

            match_identity = if source && desired_by_source.key?(source)
                               match_identity('source_ref', 'high')
                             else
                               match_identity('title', 'medium')
                             end
            dashboards[desired_title] ||= {
              id: fetch_value(entry, :id),
              title: title,
              payload: normalize_dashboard_payload(detail),
              match_identity: match_identity
            }.compact
          end
        end
        dashboards
      end

      def load_managed_slos(service)
        query = "managed_by:slo-rules-engine AND service:#{service}"
        path = "/api/v1/slo/search?#{URI.encode_www_form('page[number]' => 0, 'page[size]' => 100, query: query)}"
        response = request('GET', path)
        entries = Array(response.dig('data', 'attributes', 'slos'))

        entries.map do |entry|
          data = fetch_value(entry, :data, {})
          attributes = fetch_value(data, :attributes, {})
          tags = Array(fetch_value(attributes, :all_tags, [])).map(&:to_s)
          {
            id: fetch_value(data, :id),
            name: fetch_value(attributes, :name),
            source: extract_source_ref(tags)
          }.compact
        end
      end

      def load_managed_monitors(service)
        path = "/api/v1/monitor?#{URI.encode_www_form(monitor_tags: "#{MANAGED_MONITOR_TAG},service:#{service}")}"
        entries = Array(request('GET', path))

        entries.map do |entry|
          tags = Array(fetch_value(entry, :tags, [])).map(&:to_s)
          {
            id: fetch_value(entry, :id),
            name: fetch_value(entry, :name),
            source: extract_source_ref(tags)
          }.compact
        end
      end

      def load_managed_dashboards(service)
        dashboards = []
        lists = Array(fetch_value(request('GET', '/api/v1/dashboard/lists/manual'), :dashboard_lists, []))
        lists.each do |list|
          list_id = fetch_value(list, :id)
          next unless list_id

          path = "/api/v1/dashboard/lists/manual/#{list_id}/dashboards"
          entries = Array(fetch_value(request('GET', path), :dashboards, []))
          entries.each do |entry|
            detail = request('GET', "/api/v1/dashboard/#{fetch_value(entry, :id)}")
            tags = Array(fetch_value(detail, :tags, [])).map(&:to_s)
            next unless tags.include?(MANAGED_MONITOR_TAG)
            next unless tags.include?("service:#{service}")

            dashboards << {
              id: fetch_value(entry, :id),
              title: fetch_value(entry, :title),
              source: extract_source_ref(tags)
            }.compact
          end
        end
        dashboards
      end

      def find_slo_match(name, source)
        source_match = find_slo_by_query(source_query(source))
        return { entry: source_match, match_identity: match_identity('source_ref', 'high') } if source_match

        name_match = find_slo_by_query(name)
        return unless name_match

        { entry: name_match, match_identity: match_identity('name', 'medium') }
      end

      def find_slo_by_query(query)
        return if query.to_s.empty?

        path = "/api/v1/slo/search?#{URI.encode_www_form('page[number]' => 0, 'page[size]' => 20, query: query)}"
        response = request('GET', path)
        entries = Array(response.dig('data', 'attributes', 'slos'))
        if query.start_with?("#{MANAGED_MONITOR_TAG} AND source_ref:")
          entries.find do |entry|
            tags = Array(fetch_value(fetch_value(fetch_value(entry, :data, {}), :attributes, {}), :all_tags, [])).map(&:to_s)
            tags.include?(query.sub("#{MANAGED_MONITOR_TAG} AND ", ''))
          end
        else
          entries.find do |entry|
            fetch_value(fetch_value(entry, :data, {}), :attributes, {}).fetch('name', nil) == query
          end
        end
      end

      def find_monitor_match(name, source)
        source_match = find_monitor_by_tags(source_monitor_tags(source))
        return { entry: source_match, match_identity: match_identity('source_ref', 'high') } if source_match

        path = "/api/v1/monitor?#{URI.encode_www_form(monitor_tags: MANAGED_MONITOR_TAG, name: name)}"
        entries = Array(request('GET', path))
        name_match = entries.find { |entry| fetch_value(entry, :name) == name }
        return unless name_match

        { entry: name_match, match_identity: match_identity('name', 'medium') }
      end

      def find_monitor_by_tags(tags)
        return if tags.to_s.empty?

        path = "/api/v1/monitor?#{URI.encode_www_form(monitor_tags: tags)}"
        entries = Array(request('GET', path))
        expected_tag = tags.split(',', 2).last
        entries.find do |entry|
          Array(fetch_value(entry, :tags, [])).map(&:to_s).include?(expected_tag)
        end
      end

      def desired_name(entry, key)
        return entry if entry.is_a?(String)

        fetch_value(entry, key)
      end

      def desired_source(entry)
        return unless entry.respond_to?(:fetch)

        fetch_value(entry, :source)
      end

      def source_query(source)
        tag = source_tag(source)
        return if tag.nil?

        "#{MANAGED_MONITOR_TAG} AND #{tag}"
      end

      def source_monitor_tags(source)
        tag = source_tag(source)
        return if tag.nil?

        "#{MANAGED_MONITOR_TAG},#{tag}"
      end

      def source_tag(source)
        return if source.to_s.empty?

        "source_ref:#{normalize_source_ref(source)}"
      end

      def normalize_source_ref(source)
        source.to_s
          .gsub(/\[(\d+)\]/, '.\1')
          .gsub(/[^a-zA-Z0-9_.:-]/, '_')
          .gsub(/\.\.+/, '.')
      end

      def extract_source_ref(tags)
        tags.find { |tag| tag.start_with?('source_ref:') }&.sub('source_ref:', '')
      end

      def match_identity(strategy, confidence)
        {
          strategy: strategy,
          confidence: confidence
        }
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

      def first_resource(response)
        data = fetch_value(response, :data, response)
        return data.fetch(0, {}) if data.is_a?(Array)

        data
      end

      def normalize_slo_payload(payload)
        PayloadCanonicalizer.canonicalize('datadog.slo', payload)
      end

      def normalize_monitor_payload(payload)
        PayloadCanonicalizer.canonicalize('datadog.monitor', payload)
      end

      def normalize_dashboard_payload(payload)
        PayloadCanonicalizer.canonicalize('datadog.dashboard', payload)
      end

      def fetch_value(hash, key, default = nil)
        return hash.public_send(key) if hash.respond_to?(key)
        return default unless hash.respond_to?(:fetch)

        hash.fetch(key) { hash.fetch(key.to_s, default) }
      end
    end
  end
end
