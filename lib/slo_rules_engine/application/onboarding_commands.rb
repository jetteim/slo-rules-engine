# frozen_string_literal: true

require 'digest'
require 'json'

module SloRulesEngine
  module Application
    module OnboardingCommandSupport
      DEFAULT_LIMIT = 100
      MAX_LIMIT = 500
      SAFE_IDENTIFIER = /\A[a-zA-Z0-9][a-zA-Z0-9_.:-]*\z/
      SENSITIVE_TEXT = /(?:api[_-]?key|app[_-]?key|access[_-]?key|secret|password|token|authorization|credential)\s*[:=]/i

      private

      def normalize_list(values)
        Array(values).map(&:to_s).map(&:strip).reject(&:empty?).uniq
      end

      def validate_limit!(value, confined:)
        return nil if value.nil? && !confined

        limit = value || DEFAULT_LIMIT
        unless limit.is_a?(Integer) && limit.between?(1, MAX_LIMIT)
          raise CommandError.new(
            'invalid_candidate_limit',
            "candidate limit must be between 1 and #{MAX_LIMIT}",
            minimum: 1,
            maximum: MAX_LIMIT
          )
        end
        limit
      end

      def validate_review_request!(accepted, rejected, notes, confined:)
        if accepted.empty? && rejected.empty?
          raise CommandError.new(
            'missing_review_decision',
            'review requires at least one accepted or rejected candidate'
          )
        end
        duplicate = (accepted & rejected).first
        if duplicate
          raise CommandError.new(
            'conflicting_candidate_decision',
            'candidate cannot be both accepted and rejected',
            candidate_uid: duplicate
          )
        end
        return unless confined

        (accepted + rejected).each do |uid|
          unless uid.bytesize <= 512 && uid.match?(SAFE_IDENTIFIER)
            raise CommandError.new(
              'unsafe_agent_resource_identifier',
              'agent candidate identifier is not allowed',
              field: 'candidate_uid'
            )
          end
        end
        if notes.any? { |note| note.match?(SENSITIVE_TEXT) }
          raise CommandError.new(
            'sensitive_agent_review_note',
            'agent review notes must not contain credential-like assignments',
            field: 'notes'
          )
        end
      end

      def fingerprint(value)
        "sha256:#{Digest::SHA256.hexdigest(JSON.generate(canonicalize(value)))}"
      rescue JSON::GeneratorError
        "sha256:#{Digest::SHA256.hexdigest(value.to_s)}"
      end

      def canonicalize(value)
        case value
        when Hash
          value.keys.sort_by(&:to_s).each_with_object({}) do |key, result|
            result[key.to_s] = canonicalize(value.fetch(key))
          end
        when Array
          value.map { |item| canonicalize(item) }
        else
          value
        end
      end
    end

    class ReviewTelemetryCandidates
      include OnboardingCommandSupport

      def call(arguments, context:)
        telemetry_file = arguments.fetch('telemetry_file')
        context.input_policy.validate_lexical_paths!([
          { path: telemetry_file, field: 'telemetry_file', extensions: ['.json'] }
        ])
        limit = validate_limit!(arguments['limit'], confined: context.input_policy.confined?)
        payload = load_payload(telemetry_file, context)
        signals = SloRulesEngine::TelemetryLookup.extract_signals(payload)
        unless signals.is_a?(Array) && signals.all? { |signal| signal.is_a?(Hash) }
          raise CommandError.new(
            'invalid_candidate_evidence',
            'telemetry evidence must contain an array of signal objects',
            field: 'telemetry_file'
          )
        end

        selected = limit ? signals.first(limit) : signals
        processed_count = selected.length
        quarantine_findings = []
        if context.input_policy.confined?
          selected, quarantine_findings = sanitize_signals(selected, payload, context)
        end
        review = SloRulesEngine::Onboarding::CandidateGenerator.new.review(selected)
        review[:findings].concat(quarantine_findings)
        truncated = !limit.nil? && signals.length > limit
        if truncated
          review[:findings] << {
            code: 'candidate_results_truncated',
            message: 'Telemetry evidence exceeded the configured candidate limit.',
            details: { available: signals.length, processed: limit, limit: limit }
          }
        end
        CommandResult.new(
          value: review,
          side_effect: 'local_read',
          findings: review.fetch(:findings),
          truncation: {
            truncated: truncated,
            returned: processed_count,
            limit: limit,
            cursor: nil,
            reason: truncated ? 'raise_limit_and_reprocess_source' : nil
          }
        )
      end

      private

      def load_payload(path, context)
        resolved = context.input_policy.resolve_read_file(
          path,
          field: 'telemetry_file',
          extensions: ['.json'],
          prevalidated: true
        )
        JSON.parse(File.read(resolved), symbolize_names: true)
      rescue JSON::ParserError
        raise CommandError.new(
          'invalid_agent_input_file',
          'telemetry evidence is not valid JSON',
          field: 'telemetry_file'
        )
      end

      def sanitize_signals(signals, payload, context)
        provider = payload[:provider] if payload.is_a?(Hash)
        omitted_metrics = []
        quarantined_text = []
        safe = signals.filter_map do |signal|
          normalized = signal.each_with_object({}) { |(key, value), result| result[key.to_sym] = value }
          metric = normalized[:metric]
          unless metric.nil? || safe_metric?(metric, provider, context)
            omitted_metrics << fingerprint(metric)
            next
          end
          unless safe_short_identifier?(normalized[:kind]) && boolean?(normalized[:user_visible])
            omitted_metrics << fingerprint(normalized.slice(:kind, :metric, :user_visible))
            next
          end
          %i[sli_uid slo_uid source].each do |field|
            value = normalized[field]
            next if value.nil? || safe_short_identifier?(value)

            normalized.delete(field)
            quarantined_text << fingerprint(field => value)
          end
          %i[rationale success_condition].each do |field|
            next unless normalized.key?(field)

            quarantined_text << fingerprint(field => normalized.delete(field))
          end
          %i[objective observations_per_second failed_observations_to_alert].each do |field|
            next unless normalized.key?(field)
            next if safe_numeric_field?(field, normalized[field])

            normalized.delete(field)
            quarantined_text << fingerprint(field => 'invalid_numeric_value')
          end
          normalized
        end
        findings = []
        unless omitted_metrics.empty?
          findings << {
            code: 'unsafe_candidate_signals_omitted',
            message: 'Telemetry signals outside the safe candidate contract were omitted.',
            details: { count: omitted_metrics.length, fingerprints: omitted_metrics.first(10) }
          }
        end
        unless quarantined_text.empty?
          findings << {
            code: 'candidate_text_quarantined',
            message: 'Untrusted optional telemetry text was replaced by safe defaults or omitted.',
            details: { count: quarantined_text.length, fingerprints: quarantined_text.first(10) }
          }
        end
        [safe, findings]
      end

      def safe_metric?(metric, provider, context)
        providers = %w[datadog prometheus_stack sloth]
        candidates = providers.include?(provider.to_s) ? [provider.to_s] : providers
        candidates.any? { |candidate| context.resource_policy.valid_metric?(metric, provider: candidate) }
      end

      def safe_short_identifier?(value)
        value.is_a?(String) && value.bytesize <= 512 && value.match?(SAFE_IDENTIFIER)
      end

      def boolean?(value)
        value == true || value == false
      end

      def safe_numeric_field?(field, value)
        return false unless value.is_a?(Numeric) && value.finite?

        field == :objective ? value.positive? && value <= 1 : value >= 0
      end
    end

    class ReviewOnboardingHandoff
      include OnboardingCommandSupport

      def initialize(reviewer: SloRulesEngine::Onboarding::HandoffReviewer.new)
        @reviewer = reviewer
      end

      def call(arguments, context:)
        handoff_file = arguments.fetch('handoff_file')
        accepted = normalize_list(arguments['accept'])
        rejected = normalize_list(arguments['reject'])
        notes = normalize_list(arguments['notes'])
        validate_review_request!(accepted, rejected, notes, confined: context.input_policy.confined?)
        context.input_policy.validate_lexical_paths!([
          { path: handoff_file, field: 'handoff_file', extensions: ['.json'], access: :write }
        ])
        if arguments['validate_only'] == true
          return CommandResult.new(
            value: {
              valid: true,
              mode: 'validate_only',
              command_id: 'review-handoff',
              target: { field: 'handoff_file', path: handoff_file },
              review: {
                accepted_candidate_count: accepted.length,
                rejected_candidate_count: rejected.length,
                note_count: notes.length
              },
              io: {
                local_reads: false,
                local_writes: false,
                provider_calls: false,
                credential_loading: false
              }
            },
            side_effect: 'none'
          )
        end

        resolved_output = context.input_policy.resolve_write_file(
          handoff_file,
          field: 'handoff_file',
          extensions: ['.json'],
          prevalidated: true
        )
        resolved = context.input_policy.resolve_read_file(
          handoff_file,
          field: 'handoff_file',
          extensions: ['.json'],
          prevalidated: true
        )
        unless resolved == File.realpath(resolved_output)
          raise CommandError.new(
            'unsafe_agent_handoff_target',
            'handoff input and output must resolve to the same file',
            field: 'handoff_file'
          )
        end
        packet = @reviewer.review(
          resolved,
          accepted_candidate_uids: accepted,
          rejected_candidate_uids: rejected,
          notes: notes
        )
        value = context.input_policy.confined? ? safe_agent_result(packet, handoff_file) : packet
        CommandResult.new(
          value: value,
          side_effect: 'local_write',
          artifacts: [{ kind: 'onboarding_handoff', path: handoff_file }]
        )
      rescue SloRulesEngine::Onboarding::HandoffReviewer::ReviewError => error
        CommandResult.new(
          value: {
            valid: false,
            handoff_file: handoff_file,
            error: { code: error.code, message: error.message }
          },
          side_effect: 'local_write',
          exit_status: 1
        )
      end

      private

      def safe_agent_result(packet, handoff_file)
        review = packet.fetch(:review)
        {
          valid: true,
          handoff_file: handoff_file,
          packet_fingerprint: fingerprint(packet),
          review: {
            status: review.fetch(:status),
            accepted_candidate_uids: Array(review[:accepted_candidate_uids]),
            rejected_candidate_uids: Array(review[:rejected_candidate_uids]),
            note_count: Array(review[:notes]).length
          },
          candidate_review: {
            candidate_count: Array(packet.dig(:candidate_review, :candidates)).length,
            finding_count: Array(packet.dig(:candidate_review, :findings)).length
          },
          output_policy: {
            packet_content: 'persisted_not_inlined',
            review_notes: 'counted_not_inlined'
          }
        }
      end
    end
  end
end
