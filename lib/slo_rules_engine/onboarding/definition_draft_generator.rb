# frozen_string_literal: true

module SloRulesEngine
  module Onboarding
    class DefinitionDraftGenerator
      def initialize(candidate_generator: CandidateGenerator.new)
        @candidate_generator = candidate_generator
      end

      def generate(service:, owner:, signals:, environment: 'production')
        review = @candidate_generator.review(signals)
        lines = [
          '# Generated from telemetry inventory. Review before production use.'
        ]
        lines.concat(finding_comments(review.fetch(:findings)))
        lines.concat([
          'SRE.define do',
          "  service '#{quote(service)}'",
          "  owner '#{quote(owner)}'",
          "  description 'Draft service level definition generated from measured telemetry.'",
          "  environments '#{quote(environment)}'",
          ''
        ])
        review.fetch(:candidates).each_with_index do |candidate, index|
          lines.concat(candidate_lines(candidate, service))
          lines << '' if index < review.fetch(:candidates).length - 1
        end
        lines << 'end'
        "#{lines.join("\n")}\n"
      end

      private

      def finding_comments(findings)
        findings.map do |finding|
          parts = [
            "finding: #{finding.fetch(:code)}",
            "kind=#{finding.fetch(:kind)}",
            "metric=#{finding[:metric]}",
            finding.fetch(:message)
          ].compact
          "# #{parts.join(' ')}"
        end
      end

      def candidate_lines(candidate, service)
        proposed_slo = candidate.fetch(:proposed_slo)
        [
          '  sli do',
          "    uid '#{quote(candidate.fetch(:sli_uid))}'",
          "    title '#{quote(titleize(candidate.fetch(:sli_uid)))}'",
          '',
          "    metric '#{quote(candidate.fetch(:metric))}' do",
          "      data_source 'telemetry-inventory'",
          "      type '#{metric_type(candidate.fetch(:signal))}'",
          "      selector service: '#{quote(service)}'",
          '    end',
          '',
          '    instance do',
          "      uid 'default'",
          '',
          '      slo do',
          "        uid '#{quote(proposed_slo.fetch(:uid))}'",
          "        objective #{format_objective(proposed_slo.fetch(:objective))}",
          success_line(candidate.fetch(:signal)),
          "        calculation_basis '#{quote(proposed_slo.fetch(:calculation_basis))}'",
          "        documentation '#{quote(proposed_slo.fetch(:success_condition))}'",
          '      end',
          '    end',
          '  end'
        ]
      end

      def success_line(signal)
        case signal
        when 'latency'
          "        success_threshold '<=', 'user-reviewed latency threshold'"
        when 'freshness'
          "        success_threshold '<=', 'user-reviewed freshness threshold'"
        when 'traffic'
          "        success_threshold '>=', 'user-reviewed traffic floor'"
        when 'saturation'
          "        success_threshold '<=', 'user-reviewed saturation threshold'"
        else
          "        success_selector status: 'success'"
        end
      end

      def metric_type(signal)
        case signal
        when 'latency' then 'histogram'
        when 'traffic', 'errors', 'availability', 'user_journey' then 'counter'
        else 'gauge'
        end
      end

      def titleize(value)
        value.to_s.split('-').map(&:capitalize).join(' ')
      end

      def format_objective(value)
        value.to_f.to_s
      end

      def quote(value)
        value.to_s.gsub('\\', '\\\\\\').gsub("'", "\\\\'")
      end
    end
  end
end
