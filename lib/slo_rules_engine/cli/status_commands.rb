# frozen_string_literal: true

require 'json'
require 'optparse'

module SloRulesEngine
  module CLI
    module StatusCommands
      def status(argv)
        provider_key = nil
        manifest_path = nil
        bundle_path = nil
        portfolio_path = nil
        base_url = nil
        target_base_urls = {}
        max_age_seconds = 300
        output_path = nil
        parser = OptionParser.new do |opts|
          opts.on('--provider=PROVIDER', 'Provider key') { |value| provider_key = value }
          opts.on('--manifest=FILE', 'One reviewed provider manifest JSON file') { |value| manifest_path = value }
          opts.on('--bundle=FILE', 'One current reviewed release bundle') { |value| bundle_path = value }
          opts.on('--portfolio=FILE', 'One live-status portfolio') { |value| portfolio_path = value }
          opts.on('--base-url=URL', 'Prometheus-compatible API base URL') { |value| base_url = value }
          opts.on('--target-base-url=TARGET=URL', 'Prometheus API base URL for one aggregate target') do |value|
            target, url = value.split('=', 2)
            abort_usage('--target-base-url requires TARGET=URL') if target.to_s.empty? || url.to_s.empty?
            abort_usage("duplicate --target-base-url for #{target}") if target_base_urls.key?(target)

            target_base_urls[target] = url
          end
          opts.on('--max-age-seconds=N', Integer, 'Maximum accepted status sample age') { |value| max_age_seconds = value }
          opts.on('--output=FILE', 'Save the same live-status report printed to stdout') { |value| output_path = value }
        end
        parser.parse!(argv)
        abort_usage('status does not accept definition files') unless argv.empty?
        abort_usage('--max-age-seconds must be positive') unless max_age_seconds.positive?
        input_count = [manifest_path, bundle_path, portfolio_path].count { |path| !path.to_s.empty? }
        abort_usage('status requires exactly one of --manifest, --bundle, or --portfolio') unless input_count == 1

        if manifest_path
          abort_usage('missing --provider') if provider_key.to_s.empty?
          abort_usage('--target-base-url is only valid with --bundle or --portfolio') unless target_base_urls.empty?
          abort_usage('--bundle and --portfolio do not accept --provider') if bundle_path || portfolio_path
          return single_manifest_status(
            provider_key: provider_key,
            manifest_path: manifest_path,
            base_url: base_url || ENV.fetch('PROMETHEUS_URL', 'http://localhost:9090'),
            max_age_seconds: max_age_seconds,
            output_path: output_path
          )
        end

        abort_usage('--provider is only valid with --manifest') unless provider_key.to_s.empty?
        abort_usage('--base-url is only valid with --manifest') unless base_url.to_s.empty?
        input = if bundle_path
                  SloRulesEngine::LiveStatus::InputResolver.new.from_bundle(bundle_path)
                else
                  SloRulesEngine::LiveStatus::InputResolver.new.from_portfolio(portfolio_path)
                end
        payload = SloRulesEngine::LiveStatus::AggregateReader.new.read(
          input,
          target_base_urls: target_base_urls,
          max_age_seconds: max_age_seconds
        ).to_h
        write_status_report(payload, output_path)
      rescue SloRulesEngine::LiveStatus::AggregateError => error
        render_aggregate_status_error(error)
      end

      private

      def single_manifest_status(provider_key:, manifest_path:, base_url:, max_age_seconds:, output_path:)
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
        write_status_report(report.to_h, output_path)
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

      def write_status_report(payload, output_path)
        payload[:report] = { path: output_path } if output_path
        write_json_file(output_path, payload) if output_path
        puts JSON.pretty_generate(payload)
      end

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

      def render_aggregate_status_error(error)
        payload = {
          valid: false,
          mode: 'live_status_aggregate',
          error: {
            code: error.code,
            message: error.message
          }
        }
        payload[:findings] = error.findings unless error.findings.empty?
        puts JSON.pretty_generate(payload)
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
