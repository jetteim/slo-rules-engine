# frozen_string_literal: true

module SloRulesEngine
  module Onboarding
    class SummaryBuilder
      READINESS_ORDER = {
        'ready' => 0,
        'partial' => 1,
        'insufficient' => 2,
        'failed' => 3
      }.freeze

      def build(index_path)
        index = JSON.parse(File.read(index_path), symbolize_names: true)
        base_dir = File.dirname(index_path)
        scopes = Array(index[:scopes]).map { |entry| summarize_scope(entry, base_dir) }

        {
          provider: index[:provider],
          generated_at: index[:generated_at],
          total_scopes: index[:total_scopes] || scopes.length,
          successful_scopes: index[:successful_scopes] || scopes.count { |scope| scope[:readiness] != 'failed' },
          failed_scopes: index[:failed_scopes] || scopes.count { |scope| scope[:readiness] == 'failed' },
          summary: readiness_summary(scopes),
          scopes: scopes.sort_by { |scope| [READINESS_ORDER.fetch(scope[:readiness]), -scope[:score], scope[:label].to_s] }
        }
      end

      private

      def summarize_scope(entry, base_dir)
        if entry[:status].to_s != 'ok'
          return {
            label: entry[:label],
            scope: entry[:scope],
            status: entry[:status],
            readiness: 'failed',
            score: 0,
            signal_count: entry[:signal_count] || 0,
            candidate_count: 0,
            discovery_finding_count: entry[:finding_count] || 0,
            candidate_finding_count: 0,
            finding_codes: [entry.dig(:error, :code)].compact,
            error: entry[:error]
          }
        end

        payload = JSON.parse(File.read(File.join(base_dir, entry.fetch(:result_file))), symbolize_names: true)
        review = CandidateGenerator.new.review(payload[:signals])
        discovery_finding_codes = Array(payload[:findings]).map { |finding| finding[:code] }.compact
        candidate_finding_codes = Array(review[:findings]).map { |finding| finding[:code] }.compact
        candidate_count = Array(review[:candidates]).length
        signal_count = Array(payload[:signals]).length

        {
          label: entry[:label],
          scope: payload[:scope] || entry[:scope],
          status: entry[:status],
          readiness: readiness(candidate_count, discovery_finding_codes, candidate_finding_codes),
          score: score(candidate_count, signal_count, discovery_finding_codes.length, candidate_finding_codes.length),
          result_file: entry[:result_file],
          signal_count: signal_count,
          candidate_count: candidate_count,
          discovery_finding_count: discovery_finding_codes.length,
          candidate_finding_count: candidate_finding_codes.length,
          finding_codes: (discovery_finding_codes + candidate_finding_codes).uniq
        }
      end

      def readiness(candidate_count, discovery_finding_codes, candidate_finding_codes)
        return 'insufficient' if candidate_count.zero?
        return 'ready' if discovery_finding_codes.empty? && candidate_finding_codes.empty?

        'partial'
      end

      def score(candidate_count, signal_count, discovery_finding_count, candidate_finding_count)
        raw = (candidate_count * 30) + (signal_count * 10) - (discovery_finding_count * 5) - (candidate_finding_count * 10)
        [[raw, 0].max, 100].min
      end

      def readiness_summary(scopes)
        {
          ready_scopes: scopes.count { |scope| scope[:readiness] == 'ready' },
          partial_scopes: scopes.count { |scope| scope[:readiness] == 'partial' },
          insufficient_scopes: scopes.count { |scope| scope[:readiness] == 'insufficient' },
          failed_scopes: scopes.count { |scope| scope[:readiness] == 'failed' }
        }
      end
    end
  end
end
