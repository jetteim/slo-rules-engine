# frozen_string_literal: true

module SloRulesEngine
  module Onboarding
    class ArtifactIndexBuilder
      def build(index_path, handoff_dir: nil, draft_dir: nil, manifest_dir: nil, providers: [])
        index = JSON.parse(File.read(index_path), symbolize_names: true)
        provider_keys = provider_keys(index, manifest_dir, providers)
        scopes = Array(index[:scopes]).map do |entry|
          scope_entry(
            entry,
            base_dir: File.dirname(index_path),
            handoff_dir: handoff_dir,
            draft_dir: draft_dir,
            manifest_dir: manifest_dir,
            providers: provider_keys
          )
        end

        {
          provider: index[:provider],
          generated_at: index[:generated_at],
          artifact_index: artifact_index(index_path, handoff_dir, draft_dir, manifest_dir, provider_keys),
          summary: summary(scopes),
          scopes: scopes
        }
      end

      private

      def provider_keys(index, manifest_dir, providers)
        keys = Array(providers).map(&:to_s).reject(&:empty?)
        return keys unless keys.empty?
        return [] if manifest_dir.to_s.empty?

        [index[:provider].to_s].reject(&:empty?)
      end

      def artifact_index(index_path, handoff_dir, draft_dir, manifest_dir, providers)
        {
          discovery_index: index_path,
          handoff_dir: handoff_dir,
          draft_dir: draft_dir,
          manifest_dir: manifest_dir,
          providers: providers
        }.compact
      end

      def scope_entry(entry, base_dir:, handoff_dir:, draft_dir:, manifest_dir:, providers:)
        label = entry[:label].to_s
        service = entry.dig(:scope, :service)
        discovery = discovery_entry(entry, base_dir)
        handoff = handoff_entry(label, handoff_dir)
        draft = draft_entry(label, draft_dir)
        provider_artifacts = provider_entries(service, providers, manifest_dir, handoff_dir)
        missing = missing_artifacts(discovery, handoff, draft, provider_artifacts)
        status = scope_status(entry, missing)

        {
          label: label,
          scope: entry[:scope],
          status: status,
          discovery: discovery,
          handoff: handoff,
          draft: draft,
          providers: provider_artifacts,
          missing_artifacts: missing
        }.compact
      end

      def discovery_entry(entry, base_dir)
        path = entry[:result_file] ? File.join(base_dir, entry[:result_file]) : nil
        {
          status: entry[:status],
          path: path,
          exists: path ? File.exist?(path) : false,
          signal_count: entry[:signal_count] || 0,
          finding_count: entry[:finding_count] || 0,
          error: entry[:error]
        }.compact
      end

      def handoff_entry(label, handoff_dir)
        return nil if handoff_dir.to_s.empty?

        path = File.join(handoff_dir, "#{label}.handoff.json")
        payload = json_payload(path)
        review = payload[:review].is_a?(Hash) ? payload[:review] : {}
        {
          path: path,
          exists: File.exist?(path),
          review_status: review[:status],
          accepted_candidate_count: Array(review[:accepted_candidate_uids]).length,
          rejected_candidate_count: Array(review[:rejected_candidate_uids]).length,
          note_count: Array(review[:notes]).length
        }.compact
      end

      def draft_entry(label, draft_dir)
        return nil if draft_dir.to_s.empty?

        path = File.join(draft_dir, "#{label}.rb")
        {
          path: path,
          exists: File.exist?(path)
        }
      end

      def provider_entries(service, providers, manifest_dir, handoff_dir)
        return [] if manifest_dir.to_s.empty?

        providers.map do |provider|
          manifest_path = service ? File.join(manifest_dir, service, provider, 'manifest.json') : nil
          report_path = File.join(manifest_dir, 'manifest-review', "#{provider}.json")
          {
            provider: provider,
            manifest: {
              path: manifest_path,
              exists: manifest_path ? File.exist?(manifest_path) : false
            }.compact,
            manifest_review_report: {
              path: report_path,
              exists: File.exist?(report_path)
            },
            manifest_review_command: manifest_review_command(provider, manifest_path, report_path, handoff_dir)
          }.compact
        end
      end

      def manifest_review_command(provider, manifest_path, report_path, handoff_dir)
        return nil if manifest_path.to_s.empty?

        command = "rules-ctl manifest-review --provider=#{provider} --manifest=#{manifest_path}"
        command += " --handoff-dir=#{handoff_dir}" unless handoff_dir.to_s.empty?
        "#{command} --report=#{report_path}"
      end

      def missing_artifacts(discovery, handoff, draft, provider_artifacts)
        missing = []
        missing << missing_artifact('discovery_result', discovery[:path]) if discovery[:path] && !discovery[:exists]
        missing << missing_artifact('handoff_packet', handoff[:path]) if handoff && !handoff[:exists]
        missing << missing_artifact('draft_definition', draft[:path]) if draft && !draft[:exists]
        provider_artifacts.each do |provider|
          manifest = provider.fetch(:manifest)
          report = provider.fetch(:manifest_review_report)
          missing << missing_artifact('provider_manifest', manifest[:path], provider: provider.fetch(:provider)) unless manifest[:exists]
          missing << missing_artifact('manifest_review_report', report[:path], provider: provider.fetch(:provider)) unless report[:exists]
        end
        missing
      end

      def missing_artifact(kind, path, provider: nil)
        {
          kind: kind,
          provider: provider,
          path: path
        }.compact
      end

      def scope_status(entry, missing)
        return 'failed' if entry[:status].to_s != 'ok'
        return 'partial' unless missing.empty?

        'complete'
      end

      def summary(scopes)
        {
          total_scopes: scopes.length,
          complete_scopes: scopes.count { |scope| scope[:status] == 'complete' },
          partial_scopes: scopes.count { |scope| scope[:status] == 'partial' },
          failed_scopes: scopes.count { |scope| scope[:status] == 'failed' },
          missing_artifact_count: scopes.sum { |scope| Array(scope[:missing_artifacts]).length },
          reviewed_handoffs: scopes.count { |scope| scope.dig(:handoff, :review_status) == 'reviewed' },
          draft_files: scopes.count { |scope| scope.dig(:draft, :exists) },
          provider_manifest_files: scopes.sum { |scope| scope.fetch(:providers).count { |provider| provider.dig(:manifest, :exists) } },
          manifest_review_reports: scopes.sum { |scope| scope.fetch(:providers).count { |provider| provider.dig(:manifest_review_report, :exists) } }
        }
      end

      def json_payload(path)
        return {} unless File.exist?(path)

        JSON.parse(File.read(path), symbolize_names: true)
      rescue JSON::ParserError
        {}
      end
    end
  end
end
