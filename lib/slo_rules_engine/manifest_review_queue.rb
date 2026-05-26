# frozen_string_literal: true

require 'digest'

module SloRulesEngine
  module ManifestReviewQueue
    class ReportBuilder
      def build(manifests, provider: nil, handoff_dir: nil)
        entries = Array(manifests).each_with_index.map do |manifest, index|
          manifest_entry(manifest, index, provider, handoff_dir)
        end

        {
          valid: entries.all? { |entry| entry[:ready_for_apply] },
          provider: provider,
          total_manifests: entries.length,
          summary: summary(entries),
          freshness: freshness(manifests, entries),
          manifests: entries
        }.compact
      end

      private

      def manifest_entry(manifest, index, expected_provider, handoff_dir)
        provenance = fetch_value(manifest, :review_provenance)
        handoff = handoff_reference(provenance, handoff_dir)
        findings = provenance_findings(provenance, index, expected_provider || fetch_value(manifest, :provider), handoff)
        findings.concat(handoff_findings(provenance, index, handoff))
        status = status_for(provenance, findings)
        accepted = provenance.is_a?(Hash) ? Array(fetch_value(provenance, :accepted_candidate_uids)) : []
        rejected = provenance.is_a?(Hash) ? Array(fetch_value(provenance, :rejected_candidate_uids)) : []
        notes = provenance.is_a?(Hash) ? Array(fetch_value(provenance, :notes)) : []

        entry = {
          index: index,
          service: fetch_value(manifest, :service),
          provider: fetch_value(manifest, :provider),
          status: status,
          ready_for_apply: status == 'reviewed',
          accepted_candidate_count: accepted.length,
          rejected_candidate_count: rejected.length,
          note_count: notes.length,
          findings: findings
        }.compact
        entry[:review_provenance] = normalize_hash(provenance) if provenance.is_a?(Hash)
        entry[:handoff] = handoff_for_report(handoff) if handoff
        entry
      end

      def provenance_findings(provenance, index, expected_provider, handoff)
        path = "manifests[#{index}].review_provenance"
        unless provenance.is_a?(Hash)
          return [
            finding('missing_review_provenance', path, 'reviewed handoff provenance is required before manifest review', handoff)
          ]
        end

        findings = []
        accepted = fetch_value(provenance, :accepted_candidate_uids)
        unless accepted.is_a?(Array) && !accepted.empty?
          findings << finding(
            'missing_accepted_candidate',
            "#{path}.accepted_candidate_uids",
            'must include at least one accepted candidate',
            handoff
          )
        end

        label = fetch_value(provenance, :label)
        if label.to_s.empty?
          findings << finding('missing_provenance_label', "#{path}.label", 'is required', handoff)
        end

        provider = fetch_value(provenance, :provider)
        if provider.to_s.empty?
          findings << finding('missing_provenance_provider', "#{path}.provider", 'is required', handoff)
        elsif !expected_provider.to_s.empty? && provider.to_s != expected_provider.to_s
          findings << finding(
            'provenance_provider_mismatch',
            "#{path}.provider",
            "must match manifest provider #{expected_provider.inspect}",
            handoff
          )
        end

        findings
      end

      def status_for(provenance, findings)
        return 'missing_provenance' unless provenance.is_a?(Hash)
        return 'missing_handoff' if findings.any? { |finding| finding[:code] == 'missing_handoff_packet' }
        return 'unreviewed_handoff' if findings.any? { |finding| finding[:code] == 'unreviewed_handoff_packet' }
        return 'stale_provenance' if findings.any? { |finding| finding[:code].to_s.start_with?('stale_') }
        return 'reviewed' if findings.empty?

        'incomplete_provenance'
      end

      def summary(entries)
        {
          reviewed_manifests: entries.count { |entry| entry[:status] == 'reviewed' },
          missing_provenance_manifests: entries.count { |entry| entry[:status] == 'missing_provenance' },
          incomplete_provenance_manifests: entries.count { |entry| entry[:status] == 'incomplete_provenance' },
          stale_provenance_manifests: entries.count { |entry| entry[:status] == 'stale_provenance' },
          missing_handoff_manifests: entries.count { |entry| entry[:status] == 'missing_handoff' },
          unreviewed_handoff_manifests: entries.count { |entry| entry[:status] == 'unreviewed_handoff' },
          ready_for_apply_manifests: entries.count { |entry| entry[:ready_for_apply] },
          accepted_candidate_total: entries.sum { |entry| entry[:accepted_candidate_count] },
          rejected_candidate_total: entries.sum { |entry| entry[:rejected_candidate_count] },
          note_total: entries.sum { |entry| entry[:note_count] }
        }
      end

      def freshness(manifests, entries)
        {
          manifest_fingerprint: fingerprint(Array(manifests)),
          handoff_fingerprints: entries.filter_map { |entry| handoff_fingerprint(entry[:handoff]) }
        }
      end

      def handoff_fingerprint(handoff)
        return nil unless handoff

        payload = {
          label: handoff[:label],
          path: handoff[:path],
          exists: handoff[:exists]
        }
        payload[:fingerprint] = Digest::SHA256.hexdigest(File.binread(handoff[:path])) if handoff[:exists]
        payload
      end

      def finding(code, path, message, handoff = nil)
        payload = {
          code: code,
          path: path,
          message: message
        }
        if handoff
          payload[:handoff_label] = handoff.fetch(:label)
          payload[:handoff_file] = handoff.fetch(:path)
        end
        payload
      end

      def handoff_findings(provenance, index, handoff)
        return [] unless provenance.is_a?(Hash)
        return [] unless handoff

        path = "manifests[#{index}].review_provenance"
        unless handoff[:exists]
          return [finding('missing_handoff_packet', path, 'handoff packet is missing for reviewed provenance', handoff)]
        end

        review = handoff[:review]
        unless review.is_a?(Hash) && fetch_value(review, :status).to_s == 'reviewed'
          return [finding('unreviewed_handoff_packet', path, 'handoff packet must be reviewed before manifest review', handoff)]
        end

        stale_findings(provenance, review, path, handoff)
      end

      def stale_findings(provenance, review, path, handoff)
        [
          stale_finding(
            'stale_accepted_candidates',
            "#{path}.accepted_candidate_uids",
            'does not match accepted candidates in reviewed handoff packet',
            normalize_list(fetch_value(review, :accepted_candidate_uids)),
            normalize_list(fetch_value(provenance, :accepted_candidate_uids)),
            handoff
          ),
          stale_finding(
            'stale_rejected_candidates',
            "#{path}.rejected_candidate_uids",
            'does not match rejected candidates in reviewed handoff packet',
            normalize_list(fetch_value(review, :rejected_candidate_uids)),
            normalize_list(fetch_value(provenance, :rejected_candidate_uids)),
            handoff
          ),
          stale_finding(
            'stale_review_notes',
            "#{path}.notes",
            'does not match review notes in reviewed handoff packet',
            normalize_notes(fetch_value(review, :notes)),
            normalize_notes(fetch_value(provenance, :notes)),
            handoff
          )
        ].compact
      end

      def stale_finding(code, path, message, expected, actual, handoff)
        return nil if expected == actual

        finding(code, path, message, handoff).merge(
          expected: expected,
          actual: actual
        )
      end

      def handoff_reference(provenance, handoff_dir)
        return nil unless provenance.is_a?(Hash)
        return nil if handoff_dir.to_s.empty?

        label = fetch_value(provenance, :label).to_s
        return nil if label.empty?

        path = File.join(handoff_dir, "#{label}.handoff.json")
        {
          label: label,
          path: path,
          exists: File.exist?(path)
        }.merge(handoff_payload(path))
      end

      def handoff_payload(path)
        return {} unless File.exist?(path)

        payload = JSON.parse(File.read(path), symbolize_names: true)
        {
          provider: payload[:provider],
          review: payload[:review]
        }.compact
      rescue JSON::ParserError
        {}
      end

      def handoff_for_report(handoff)
        review = handoff[:review]
        {
          label: handoff[:label],
          path: handoff[:path],
          exists: handoff[:exists],
          provider: handoff[:provider],
          review_status: review.is_a?(Hash) ? fetch_value(review, :status) : nil
        }.compact
      end

      def normalize_hash(value)
        value.to_h.each_with_object({}) do |(key, entry), normalized|
          normalized[key.to_sym] = entry
        end
      end

      def normalize_list(value)
        Array(value).map(&:to_s).sort
      end

      def normalize_notes(value)
        Array(value).map(&:to_s)
      end

      def fingerprint(value)
        Digest::SHA256.hexdigest(JSON.generate(canonicalize(value)))
      end

      def canonicalize(value)
        case value
        when Hash
          value.keys.sort_by(&:to_s).each_with_object({}) do |key, canonical|
            canonical[key.to_s] = canonicalize(value[key])
          end
        when Array
          value.map { |entry| canonicalize(entry) }
        else
          value
        end
      end

      def fetch_value(container, key)
        return container[key] if container.is_a?(Hash) && container.key?(key)
        return container[key.to_s] if container.is_a?(Hash) && container.key?(key.to_s)

        nil
      end
    end
  end
end
