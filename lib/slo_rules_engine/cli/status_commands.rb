# frozen_string_literal: true

require 'json'
require 'optparse'

module SloRulesEngine
  module CLI
    module StatusCommands
      def status(argv)
        provider_key = nil
        manifest_path = nil
        base_url = ENV.fetch('PROMETHEUS_URL', 'http://localhost:9090')
        max_age_seconds = 300
        output_path = nil
        parser = OptionParser.new do |opts|
          opts.on('--provider=PROVIDER', 'Provider key') { |value| provider_key = value }
          opts.on('--manifest=FILE', 'One reviewed provider manifest JSON file') { |value| manifest_path = value }
          opts.on('--base-url=URL', 'Prometheus-compatible API base URL') { |value| base_url = value }
          opts.on('--max-age-seconds=N', Integer, 'Maximum accepted status sample age') { |value| max_age_seconds = value }
          opts.on('--output=FILE', 'Save the same live-status report printed to stdout') { |value| output_path = value }
        end
        parser.parse!(argv)
        abort_usage('status does not accept definition files') unless argv.empty?
        abort_usage('missing --provider') if provider_key.to_s.empty?
        abort_usage('missing --manifest') if manifest_path.to_s.empty?
        abort_usage('--max-age-seconds must be positive') unless max_age_seconds.positive?

        provider = SloRulesEngine.default_provider_registry.fetch(provider_key)
        unless provider.key == 'prometheus_stack'
          render_unsupported_status_provider(provider)
        end

        manifests = load_apply_manifests(manifest_path, provider)
        abort_usage('status requires exactly one reviewed manifest') unless manifests.length == 1
        validate_status_review_evidence!(manifests, provider)

        report = SloRulesEngine::LiveStatus::PrometheusReader.new(
          client: SloRulesEngine::TelemetryLookup::Prometheus::Client.new(base_url: base_url),
          max_age_seconds: max_age_seconds
        ).read(manifests.fetch(0))
        payload = report.to_h
        payload[:report] = { path: output_path } if output_path
        write_json_file(output_path, payload) if output_path
        puts JSON.pretty_generate(payload)
      rescue SloRulesEngine::ManifestSchemaError => error
        render_manifest_schema_error(
          provider: provider,
          provider_key: provider_key,
          mode: 'live_status',
          error: error
        )
      rescue SloRulesEngine::LiveStatus::UnsupportedProvider
        render_unsupported_status_provider(provider)
      end

      private

      def validate_status_review_evidence!(manifests, provider)
        result = SloRulesEngine::ManifestReviewEvidenceValidator.validate(manifests)
        return if result.valid?

        puts JSON.pretty_generate(
          valid: false,
          provider: provider.key,
          mode: 'live_status',
          error: {
            code: 'missing_review_evidence',
            message: 'live status requires reviewed handoff provenance in the manifest'
          },
          errors: result.errors.map(&:to_h),
          warnings: result.warnings.map(&:to_h)
        )
        exit 1
      end

      def render_unsupported_status_provider(provider)
        puts JSON.pretty_generate(
          valid: false,
          provider: provider&.key,
          mode: 'live_status',
          error: {
            code: 'unsupported_live_status_provider',
            message: 'live status currently supports only provider "prometheus_stack"'
          }
        )
        exit 1
      end
    end
  end
end
