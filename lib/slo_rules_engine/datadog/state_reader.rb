# frozen_string_literal: true

require 'uri'

module SloRulesEngine
  module Datadog
    class StateReader
      MANAGED_MONITOR_TAG = 'managed_by:slo-rules-engine'
      DASHBOARD_PAGE_SIZE = 100

      def initialize(requester:)
        @requester = requester
      end

      def existing_state(desired: {})
        {
          slos: load_slos(Array(fetch_value(desired, :slos, []))),
          monitors: load_monitors(Array(fetch_value(desired, :monitors, []))),
          dashboards: load_dashboards(Array(fetch_value(desired, :dashboards, [])))
        }
      end

      def managed_state(service:)
        {
          slos: load_managed_slos(service),
          monitors: load_managed_monitors(service),
          dashboards: load_managed_dashboards(service)
        }
      end

      private

      def request(method, path)
        @requester.request(method, path)
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
        source_matches_by_title = Hash.new { |hash, key| hash[key] = [] }
        title_matches_by_title = Hash.new { |hash, key| hash[key] = [] }
        dashboard_catalog.each do |entry|
          source = extract_source_ref(entry.fetch(:tags))
          title = entry.fetch(:title)
          match = entry.slice(:id, :title, :payload)
          if source && desired_by_source.key?(source)
            source_matches_by_title[desired_by_source.fetch(source)] << match
          elsif entry.fetch(:tags).include?(MANAGED_MONITOR_TAG) && desired_by_title.key?(title)
            title_matches_by_title[desired_by_title.fetch(title)] << match
          end
        end
        desired_titles.each_with_object({}) do |entry, dashboards|
          desired_title = entry.fetch(:title)
          matches = source_matches_by_title[desired_title]
          strategy = 'source_ref'
          if matches.empty?
            matches = title_matches_by_title[desired_title]
            strategy = 'title'
          end
          next if matches.empty?

          dashboards[desired_title] = matches.first.merge(
            match_identity: match_identity_for_matches(strategy, matches.length)
          )
        end
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
        dashboard_catalog.filter_map do |entry|
          tags = entry.fetch(:tags)
          next unless tags.include?(MANAGED_MONITOR_TAG)
          next unless tags.include?("service:#{service}")

          {
            id: entry.fetch(:id),
            title: entry.fetch(:title),
            source: extract_source_ref(tags)
          }.compact
        end
      end

      def dashboard_catalog
        dashboard_summaries.filter_map do |summary|
          id = fetch_value(summary, :id)
          next unless id

          detail = request('GET', "/api/v1/dashboard/#{id}")
          {
            id: fetch_value(detail, :id) || id,
            title: fetch_value(detail, :title) || fetch_value(summary, :title),
            tags: Array(fetch_value(detail, :tags, [])).map(&:to_s),
            payload: normalize_dashboard_payload(detail)
          }
        end
      end

      def dashboard_summaries
        start = 0
        summaries = []
        loop do
          query = URI.encode_www_form(count: DASHBOARD_PAGE_SIZE, start: start)
          page = Array(fetch_value(request('GET', "/api/v1/dashboard?#{query}"), :dashboards, []))
          summaries.concat(page)
          break if page.length < DASHBOARD_PAGE_SIZE

          start += page.length
        end
        summaries
      end

      def find_slo_match(name, source)
        source_matches = find_slo_matches_by_query(source_query(source))
        source_match = build_match(source_matches, 'source_ref')
        return source_match if source_match

        build_match(find_slo_matches_by_query(name), 'name')
      end

      def find_slo_matches_by_query(query)
        return [] if query.to_s.empty?

        path = "/api/v1/slo/search?#{URI.encode_www_form('page[number]' => 0, 'page[size]' => 20, query: query)}"
        response = request('GET', path)
        entries = Array(response.dig('data', 'attributes', 'slos'))
        if query.start_with?("#{MANAGED_MONITOR_TAG} AND source_ref:")
          entries.select do |entry|
            tags = Array(fetch_value(fetch_value(fetch_value(entry, :data, {}), :attributes, {}), :all_tags, [])).map(&:to_s)
            tags.include?(query.sub("#{MANAGED_MONITOR_TAG} AND ", ''))
          end
        else
          entries.select do |entry|
            attributes = fetch_value(fetch_value(entry, :data, {}), :attributes, {})
            tags = Array(fetch_value(attributes, :all_tags, [])).map(&:to_s)
            fetch_value(attributes, :name) == query && tags.include?(MANAGED_MONITOR_TAG)
          end
        end
      end

      def find_monitor_match(name, source)
        source_matches = find_monitor_matches_by_tags(source_monitor_tags(source))
        source_match = build_match(source_matches, 'source_ref')
        return source_match if source_match

        path = "/api/v1/monitor?#{URI.encode_www_form(monitor_tags: MANAGED_MONITOR_TAG, name: name)}"
        entries = Array(request('GET', path))
        build_match(entries.select { |entry| fetch_value(entry, :name) == name }, 'name')
      end

      def find_monitor_matches_by_tags(tags)
        return [] if tags.to_s.empty?

        path = "/api/v1/monitor?#{URI.encode_www_form(monitor_tags: tags)}"
        entries = Array(request('GET', path))
        expected_tag = tags.split(',', 2).last
        entries.select do |entry|
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

      def build_match(entries, strategy)
        return if entries.empty?

        { entry: entries.first, match_identity: match_identity_for_matches(strategy, entries.length) }
      end

      def match_identity_for_matches(strategy, count)
        return match_identity(strategy, base_confidence_for(strategy)) if count == 1

        match_identity("ambiguous_#{strategy}", 'low')
      end

      def base_confidence_for(strategy)
        {
          'source_ref' => 'high',
          'name' => 'medium',
          'title' => 'medium'
        }.fetch(strategy)
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
