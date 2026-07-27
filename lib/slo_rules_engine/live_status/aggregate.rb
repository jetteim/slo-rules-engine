# frozen_string_literal: true

require 'json'
require 'pathname'
require 'uri'

module SloRulesEngine
  module LiveStatus
    AGGREGATE_SCHEMA_VERSION = 'slo-rules-engine/live-slo-status-aggregate/v1'
    AGGREGATE_KIND = 'LiveSLOStatusAggregateReport'
    PORTFOLIO_SCHEMA_VERSION = 'slo-rules-engine/live-status-portfolio/v1'
    PORTFOLIO_KIND = 'LiveStatusPortfolio'
    LIVE_STATUS_PROVIDERS = %w[prometheus_stack].freeze

    class AggregateError < StandardError
      attr_reader :code, :findings

      def initialize(code, message, findings: [])
        @code = code
        @findings = findings
        super(message)
      end
    end

    ResolvedInput = Struct.new(:scope, :source, :targets, keyword_init: true)

    AggregateReport = Struct.new(
      :scope,
      :source,
      :checked_at,
      :max_age_seconds,
      :targets,
      keyword_init: true
    ) do
      def to_h
        {
          schema_version: AGGREGATE_SCHEMA_VERSION,
          kind: AGGREGATE_KIND,
          scope: scope,
          source: source,
          checked_at: checked_at,
          max_age_seconds: max_age_seconds,
          summary: summary,
          targets: targets
        }
      end

      private

      def summary
        states = STATES.to_h { |state| [state.to_sym, 0] }
        slo_count = 0
        targets.each do |target|
          next unless target.fetch(:outcome) == 'reported'

          statuses = Array(target.dig(:report, :statuses))
          slo_count += statuses.length
          statuses.each do |status|
            state = status[:state].to_s
            states[state.to_sym] += 1 if states.key?(state.to_sym)
          end
        end
        unsupported = targets.count { |target| target.fetch(:outcome) == 'unsupported' }
        evidence_incomplete = unsupported.positive? ||
          states.fetch(:missing_telemetry).positive? ||
          states.fetch(:unverifiable).positive? ||
          slo_count.zero?

        {
          target_count: targets.length,
          reported_targets: targets.length - unsupported,
          unsupported_targets: unsupported,
          slo_count: slo_count
        }.merge(states).merge(
          coverage_complete: unsupported.zero?,
          evidence_complete: !evidence_incomplete
        )
      end
    end

    class InputResolver
      def from_bundle(path)
        expanded_path = File.expand_path(path)
        bundle = parse_json(expanded_path, code: 'invalid_live_status_bundle')
        status = SloRulesEngine::ReleaseBundle::StatusEvaluator.new.evaluate(bundle)
        unless status.fetch(:valid)
          code = status.fetch(:effective_lifecycle) == 'stale' ?
            'stale_live_status_bundle' :
            'invalid_live_status_bundle'
          raise AggregateError.new(
            code,
            'release bundle is not current and review-ready for live status',
            findings: status.fetch(:findings)
          )
        end

        artifacts = Array(fetch_value(bundle, :artifacts)).to_h do |artifact|
          [fetch_value(artifact, :uid).to_s, artifact]
        end
        targets = Array(fetch_value(bundle, :targets)).map do |target|
          uid = fetch_value(target, :uid).to_s
          artifact = artifacts[fetch_value(target, :manifest_artifact_uid).to_s]
          manifest = fetch_value(artifact, :content)
          unless manifest.is_a?(Hash)
            raise AggregateError.new(
              'invalid_live_status_bundle',
              "release bundle target #{uid.inspect} has no embedded provider manifest"
            )
          end

          resolved_target(uid, manifest)
        end
        validate_targets!(targets, code: 'invalid_live_status_bundle')

        ResolvedInput.new(
          scope: 'release_bundle',
          source: {
            path: expanded_path,
            bundle_id: fetch_value(bundle, :bundle_id),
            lifecycle: status.fetch(:effective_lifecycle),
            fingerprint: SloRulesEngine::ReleaseBundle::Fingerprint.content(bundle)
          },
          targets: targets.sort_by { |target| target.fetch(:uid) }
        )
      rescue JSON::ParserError, Errno::ENOENT, Errno::EACCES => error
        raise AggregateError.new('invalid_live_status_bundle', "cannot read release bundle: #{error.message}")
      end

      def from_portfolio(path)
        expanded_path = File.expand_path(path)
        portfolio = parse_json(expanded_path, code: 'invalid_live_status_portfolio')
        validate_portfolio_header!(portfolio)
        entries = fetch_value(portfolio, :targets)
        unless entries.is_a?(Array) && !entries.empty?
          raise AggregateError.new(
            'invalid_live_status_portfolio',
            'live-status portfolio must contain at least one target'
          )
        end

        manifest_sources = []
        targets = entries.map.with_index do |entry, index|
          unless entry.is_a?(Hash)
            raise AggregateError.new(
              'invalid_live_status_portfolio',
              "live-status portfolio target #{index} must be an object"
            )
          end
          uid = fetch_value(entry, :uid).to_s
          manifest_reference = fetch_value(entry, :manifest).to_s
          if uid.empty? || manifest_reference.empty?
            raise AggregateError.new(
              'invalid_live_status_portfolio',
              "live-status portfolio target #{index} requires uid and manifest"
            )
          end
          manifest_path = expand_reference(manifest_reference, expanded_path)
          manifest = parse_json(manifest_path, code: 'invalid_live_status_portfolio')
          manifest_sources << {
            uid: uid,
            path: manifest_path,
            fingerprint: SloRulesEngine::ReleaseBundle::Fingerprint.content(manifest)
          }
          resolved_target(uid, manifest)
        end
        validate_targets!(targets, code: 'invalid_live_status_portfolio')

        ResolvedInput.new(
          scope: 'portfolio',
          source: {
            path: expanded_path,
            fingerprint: SloRulesEngine::ReleaseBundle::Fingerprint.content(portfolio),
            manifests: manifest_sources.sort_by { |source| source.fetch(:uid) }
          },
          targets: targets.sort_by { |target| target.fetch(:uid) }
        )
      rescue JSON::ParserError, Errno::ENOENT, Errno::EACCES => error
        raise AggregateError.new('invalid_live_status_portfolio', "cannot read live-status portfolio: #{error.message}")
      end

      private

      def parse_json(path, code:)
        JSON.parse(File.read(path))
      rescue JSON::ParserError, Errno::ENOENT, Errno::EACCES => error
        raise AggregateError.new(code, "cannot read #{path}: #{error.message}")
      end

      def validate_portfolio_header!(portfolio)
        unless portfolio.is_a?(Hash) &&
               fetch_value(portfolio, :schema_version) == PORTFOLIO_SCHEMA_VERSION &&
               fetch_value(portfolio, :kind) == PORTFOLIO_KIND
          raise AggregateError.new(
            'invalid_live_status_portfolio',
            "live-status portfolio must be #{PORTFOLIO_SCHEMA_VERSION} #{PORTFOLIO_KIND}"
          )
        end
        credential_paths = SloRulesEngine::ReleaseBundle::CredentialScanner.paths(portfolio, 'portfolio')
        return if credential_paths.empty?

        raise AggregateError.new(
          'invalid_live_status_portfolio',
          'live-status portfolio must not contain credentials',
          findings: credential_paths.map do |credential_path|
            {
              code: 'credential_like_key',
              path: credential_path,
              message: 'credential-like keys are forbidden in live-status portfolios'
            }
          end
        )
      end

      def expand_reference(reference, portfolio_path)
        path = Pathname.new(reference)
        return path.expand_path.to_s if path.absolute?

        path.expand_path(File.dirname(portfolio_path)).to_s
      end

      def resolved_target(uid, manifest)
        provider = fetch_value(manifest, :provider).to_s
        service = fetch_value(manifest, :service).to_s
        expected_uid = "#{service}/#{provider}"
        unless uid == expected_uid
          raise AggregateError.new(
            'invalid_live_status_target',
            "live-status target #{uid.inspect} must match manifest identity #{expected_uid.inspect}"
          )
        end

        {
          uid: uid,
          service: service,
          provider: provider,
          manifest: manifest
        }
      end

      def validate_targets!(targets, code:)
        duplicates = targets.group_by { |target| target.fetch(:uid) }
          .select { |_uid, entries| entries.length > 1 }
          .keys
        unless duplicates.empty?
          raise AggregateError.new(
            'duplicate_live_status_target',
            "live-status target UIDs must be unique: #{duplicates.sort.join(', ')}"
          )
        end

        manifests = targets.map { |target| target.fetch(:manifest) }
        manifests.each { |manifest| SloRulesEngine::ManifestSchemaValidator.validate!(manifest) }
        review = SloRulesEngine::ManifestReviewEvidenceValidator.validate(manifests)
        return if review.valid?

        raise AggregateError.new(
          'missing_review_evidence',
          'aggregate live status requires reviewed handoff provenance in every manifest',
          findings: review.errors.map(&:to_h)
        )
      rescue SloRulesEngine::ManifestSchemaError => error
        raise AggregateError.new(
          code,
          'aggregate live status requires valid provider manifests',
          findings: error.result.errors.map(&:to_h)
        )
      end

      def fetch_value(container, key)
        return container[key] if container.is_a?(Hash) && container.key?(key)
        return container[key.to_s] if container.is_a?(Hash) && container.key?(key.to_s)

        nil
      end
    end

    class AggregateReader
      def initialize(
        client_factory: ->(base_url) { SloRulesEngine::TelemetryLookup::Prometheus::Client.new(base_url: base_url) },
        clock: -> { Time.now.utc }
      )
        @client_factory = client_factory
        @clock = clock
      end

      def read(input, target_base_urls:, max_age_seconds: 300)
        max_age_seconds = Integer(max_age_seconds)
        raise AggregateError.new(
          'invalid_live_status_runtime',
          'max_age_seconds must be positive'
        ) unless max_age_seconds.positive?

        runtimes = validate_runtimes!(input.targets, target_base_urls)
        checked_at = @clock.call.utc
        targets = input.targets.sort_by { |target| target.fetch(:uid) }.map do |target|
          if supported?(target)
            report = PrometheusReader.new(
              client: @client_factory.call(runtimes.fetch(target.fetch(:uid))),
              clock: -> { checked_at },
              max_age_seconds: max_age_seconds
            ).read(target.fetch(:manifest))
            {
              uid: target.fetch(:uid),
              service: target.fetch(:service),
              provider: target.fetch(:provider),
              outcome: 'reported',
              report: report.to_h
            }
          else
            unsupported_target(target)
          end
        end

        AggregateReport.new(
          scope: input.scope,
          source: input.source,
          checked_at: checked_at.iso8601,
          max_age_seconds: max_age_seconds,
          targets: targets
        )
      rescue ArgumentError, TypeError => error
        raise AggregateError.new('invalid_live_status_runtime', error.message)
      end

      private

      def validate_runtimes!(targets, target_base_urls)
        runtimes = target_base_urls.to_h.transform_keys(&:to_s)
        known_uids = targets.map { |target| target.fetch(:uid) }
        unknown = runtimes.keys - known_uids
        unless unknown.empty?
          raise AggregateError.new(
            'unknown_live_status_runtime',
            "runtime mappings do not match input targets: #{unknown.sort.join(', ')}"
          )
        end

        supported = targets.select { |target| supported?(target) }
        if supported.empty?
          raise AggregateError.new(
            'no_supported_live_status_targets',
            'aggregate live status has no Prometheus Stack targets to read'
          )
        end
        unsupported_mappings = runtimes.keys & (known_uids - supported.map { |target| target.fetch(:uid) })
        unless unsupported_mappings.empty?
          raise AggregateError.new(
            'unknown_live_status_runtime',
            "runtime mappings are not accepted for unsupported targets: #{unsupported_mappings.sort.join(', ')}"
          )
        end
        missing = supported.map { |target| target.fetch(:uid) } - runtimes.keys
        unless missing.empty?
          raise AggregateError.new(
            'missing_live_status_runtime',
            "missing Prometheus base URL for targets: #{missing.sort.join(', ')}"
          )
        end

        runtimes.each_value { |base_url| validate_base_url!(base_url) }
        runtimes
      end

      def validate_base_url!(base_url)
        uri = URI.parse(base_url.to_s)
        valid = %w[http https].include?(uri.scheme) &&
          !uri.host.to_s.empty? &&
          uri.userinfo.nil? &&
          uri.query.nil? &&
          uri.fragment.nil?
        return if valid

        raise AggregateError.new(
          'invalid_live_status_runtime',
          'Prometheus base URLs must use HTTP(S), include a host, and exclude credentials, query, and fragment'
        )
      rescue URI::InvalidURIError
        raise AggregateError.new('invalid_live_status_runtime', 'Prometheus base URL is invalid')
      end

      def supported?(target)
        LIVE_STATUS_PROVIDERS.include?(target.fetch(:provider))
      end

      def unsupported_target(target)
        {
          uid: target.fetch(:uid),
          service: target.fetch(:service),
          provider: target.fetch(:provider),
          outcome: 'unsupported',
          findings: [
            {
              code: 'unsupported_live_status_provider',
              message: "live status is not implemented for provider #{target.fetch(:provider).inspect}",
              severity: 'info'
            }
          ]
        }
      end
    end
  end
end
