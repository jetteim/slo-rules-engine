# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'time'

module SloRulesEngine
  module TelemetryBatchDiscovery
    MAX_SCOPES = 100
    SCOPE_KEYS = %i[label service selectors host].freeze
    Scope = Struct.new(:label, :service, :selectors, :host, keyword_init: true) do
      def to_h
        {
          label: label,
          service: service,
          selectors: selectors,
          host: host
        }.compact
      end
    end

    module_function

    def load_scopes(path, provider:)
      payload = JSON.parse(File.read(path), symbolize_names: true)
      raise ArgumentError, 'scope file must contain a JSON array' unless payload.is_a?(Array)
      unless payload.length.between?(1, MAX_SCOPES)
        raise ArgumentError, "scope file must contain between 1 and #{MAX_SCOPES} entries"
      end

      scopes = payload.each_with_index.map do |entry, index|
        raise ArgumentError, "scope entry #{index} must be an object" unless entry.is_a?(Hash)
        unknown_keys = entry.keys - SCOPE_KEYS
        raise ArgumentError, "scope entry #{index} contains unsupported fields" unless unknown_keys.empty?
        raise ArgumentError, "scope entry #{index} selectors must be an object" unless (entry[:selectors] || {}).is_a?(Hash)

        selectors = (entry[:selectors] || {}).transform_keys(&:to_s)
        scope = Scope.new(
          label: normalize_label(entry[:label] || default_label(entry, index)),
          service: entry[:service],
          selectors: selectors,
          host: entry[:host]
        )
        validate_scope!(scope, provider: provider, index: index)
        scope
      end

      duplicate = scopes.map(&:label).find { |label| scopes.count { |scope| scope.label == label } > 1 }
      raise ArgumentError, "duplicate normalized label #{duplicate.inspect}" if duplicate

      scopes
    end

    def normalize_label(value)
      value.to_s.strip.downcase.gsub(/[^a-z0-9._-]+/, '-').gsub(/-+/, '-').gsub(/\A-|-\z/, '')
    end

    def default_label(entry, index)
      return entry[:service] unless entry[:service].to_s.empty?
      return entry[:host] unless entry[:host].to_s.empty?

      "scope-#{index + 1}"
    end

    def validate_scope!(scope, provider:, index:)
      if scope.service.to_s.empty? && scope.selectors.to_h.empty? && scope.host.to_s.empty?
        raise ArgumentError, "scope entry #{index} must define at least one of service, selectors, or host"
      end

      raise ArgumentError, "scope entry #{index} has empty normalized label" if scope.label.to_s.empty?

      if provider == 'datadog' && !scope.host.to_s.empty? && (!scope.service.to_s.empty? || !scope.selectors.to_h.empty?)
        raise ArgumentError, 'Datadog scope entries cannot combine host with service or selectors'
      end

      if provider != 'datadog' && !scope.host.to_s.empty?
        raise ArgumentError, 'host scope is only supported for datadog discovery'
      end
    end

    class Runner
      def initialize(provider:, adapter:, output_dir:, time_fn: -> { Time.now.utc.iso8601 }, path_policy: nil)
        @provider = provider
        @adapter = adapter
        @output_dir = output_dir
        @time_fn = time_fn
        @path_policy = path_policy
      end

      def run(scopes)
        FileUtils.mkdir_p(@output_dir)
        scope_results = scopes.map { |scope| run_scope(scope) }
        index_payload = {
          provider: @provider,
          generated_at: @time_fn.call,
          total_scopes: scope_results.length,
          successful_scopes: scope_results.count { |entry| entry.fetch(:status) == 'ok' },
          failed_scopes: scope_results.count { |entry| entry.fetch(:status) == 'error' },
          scopes: scope_results
        }
        File.write(output_path('index.json'), JSON.pretty_generate(index_payload))
        index_payload
      end

      private

      def run_scope(scope)
        result = @adapter.discover(service: scope.service, selectors: scope.selectors || {}, host: scope.host)
        payload = result.to_h.merge(scope: scope.to_h)
        file_name = "#{scope.label}.json"
        File.write(output_path(file_name), JSON.pretty_generate(payload))
        truncation = payload.fetch(:findings).find { |finding| finding[:code] == 'telemetry_results_truncated' }
        {
          label: scope.label,
          scope: scope.to_h,
          status: 'ok',
          result_file: file_name,
          signal_count: payload.fetch(:signals).length,
          finding_count: payload.fetch(:findings).length,
          truncated: !truncation.nil?,
          limit: truncation&.dig(:details, :limit)
        }
      rescue StandardError => error
        {
          label: scope.label,
          scope: scope.to_h,
          status: 'error',
          signal_count: 0,
          finding_count: 0,
          error: {
            code: 'discovery_failed',
            message: 'Telemetry discovery failed for this scope.',
            error_class: error.class.name
          }
        }
      end

      def output_path(file_name)
        return File.join(@output_dir, file_name) unless @path_policy

        @path_policy.resolve_write_child(@output_dir, [file_name], field: 'discovery_artifacts')
      end
    end
  end
end
