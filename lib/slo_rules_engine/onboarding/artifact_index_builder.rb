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
            index_path: index_path,
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

      def scope_entry(entry, index_path:, base_dir:, handoff_dir:, draft_dir:, manifest_dir:, providers:)
        label = entry[:label].to_s
        service = entry.dig(:scope, :service)
        discovery = discovery_entry(entry, base_dir)
        handoff = handoff_entry(label, handoff_dir)
        draft = draft_entry(label, draft_dir)
        provider_artifacts = provider_entries(service, providers, manifest_dir, handoff_dir)
        missing = missing_artifacts(discovery, handoff, draft, provider_artifacts)
        status = scope_status(entry, missing, provider_artifacts)
        next_actions = next_actions(
          entry,
          discovery: discovery,
          handoff: handoff,
          draft: draft,
          providers: provider_artifacts,
          index_path: index_path,
          handoff_dir: handoff_dir,
          manifest_dir: manifest_dir
        )

        {
          label: label,
          scope: entry[:scope],
          status: status,
          discovery: discovery,
          handoff: handoff,
          draft: draft,
          providers: provider_artifacts,
          missing_artifacts: missing,
          next_actions: next_actions
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
            manifest_review_report: manifest_review_report_entry(
              report_path,
              provider: provider,
              manifest_path: manifest_path,
              manifest_dir: manifest_dir,
              handoff_dir: handoff_dir
            ),
            manifest_review_command: manifest_review_command(provider, manifest_path, report_path, handoff_dir)
          }.compact
        end
      end

      def manifest_review_report_entry(path, provider:, manifest_path:, manifest_dir:, handoff_dir:)
        exists = File.exist?(path)
        payload = json_payload(path)
        summary = payload[:summary].is_a?(Hash) ? payload[:summary] : {}
        entry = {
          path: path,
          exists: exists
        }
        if exists
          entry[:valid] = payload[:valid] unless payload[:valid].nil?
          entry[:ready_for_apply_manifests] = summary[:ready_for_apply_manifests] if summary.key?(:ready_for_apply_manifests)
          entry[:finding_codes] = manifest_review_finding_codes(payload)
          freshness = saved_report_freshness(
            payload,
            provider: provider,
            manifest_path: manifest_path,
            manifest_dir: manifest_dir,
            handoff_dir: handoff_dir,
            report_path: path
          )
          if freshness
            entry[:fresh] = freshness[:fresh]
            entry[:freshness_finding_codes] = Array(freshness[:findings]).map { |finding| finding[:code] }.compact.uniq
          end
        end
        entry
      end

      def saved_report_freshness(saved_report, provider:, manifest_path:, manifest_dir:, handoff_dir:, report_path:)
        manifests = current_provider_manifests(provider, manifest_dir)
        if manifests.empty?
          return nil if manifest_path.to_s.empty? || !File.exist?(manifest_path)

          manifests = [json_payload(manifest_path)]
        end

        current_report = SloRulesEngine::ManifestReviewQueue::ReportBuilder.new.build(
          manifests,
          provider: provider,
          handoff_dir: handoff_dir
        )
        SloRulesEngine::ManifestReviewQueue::FreshnessValidator.new.validate(saved_report, current_report, path: report_path)
      end

      def current_provider_manifests(provider, manifest_dir)
        return [] if manifest_dir.to_s.empty?

        Dir.glob(File.join(manifest_dir, '*', provider, 'manifest.json')).sort.map do |path|
          json_payload(path)
        end
      end

      def manifest_review_finding_codes(payload)
        Array(payload[:manifests]).flat_map do |manifest|
          Array(manifest[:findings]).map { |finding| finding[:code] }
        end.compact.uniq
      end

      def manifest_review_command(provider, manifest_path, report_path, handoff_dir)
        return nil if manifest_path.to_s.empty?

        manifest_review_command_with_option(provider, manifest_path, report_path, handoff_dir, option: 'report')
      end

      def manifest_review_refresh_command(provider, manifest_path, report_path, handoff_dir)
        return nil if manifest_path.to_s.empty?

        manifest_review_command_with_option(provider, manifest_path, report_path, handoff_dir, option: 'output')
      end

      def manifest_review_command_with_option(provider, manifest_path, report_path, handoff_dir, option:)
        command = "rules-ctl manifest-review --provider=#{provider} --manifest=#{manifest_path}"
        command += " --handoff-dir=#{handoff_dir}" unless handoff_dir.to_s.empty?
        "#{command} --#{option}=#{report_path}"
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

      def next_actions(entry, discovery:, handoff:, draft:, providers:, index_path:, handoff_dir:, manifest_dir:)
        actions = []
        label = entry[:label].to_s
        service = entry.dig(:scope, :service)

        if discovery[:status].to_s != 'ok' || (discovery[:path] && !discovery[:exists])
          actions << next_action(
            :rerun_discovery,
            "refresh telemetry discovery evidence for #{label}",
            path: discovery[:path]
          )
        end

        if handoff && !handoff[:exists]
          actions << next_action(
            :create_handoff_packet,
            "write the onboarding handoff packet for #{label}",
            path: handoff[:path],
            command: "rules-ctl onboarding-summary --handoff-dir=#{handoff_dir} #{index_path}"
          )
        elsif handoff && handoff[:review_status].to_s != 'reviewed'
          actions << next_action(
            :review_handoff,
            "accept or reject candidate SLOs for #{label}",
            path: handoff[:path],
            command: "rules-ctl review-handoff --accept=<candidate_uid> #{handoff[:path]}"
          )
        end

        if draft && !draft[:exists]
          command = nil
          if handoff && handoff[:path]
            command = "rules-ctl draft-from-handoff --service=#{service} --owner=<owner> #{handoff[:path]} > #{draft[:path]}"
          end
          actions << next_action(
            :generate_reviewed_draft,
            "generate a reviewed draft definition for #{label}",
            path: draft[:path],
            command: command
          )
        end

        providers.each do |provider|
          provider_key = provider.fetch(:provider)
          manifest = provider.fetch(:manifest)
          report = provider.fetch(:manifest_review_report)
          unless manifest[:exists]
            command = nil
            if draft && draft[:path]
              command = "rules-ctl generate --provider=#{provider_key} --output-dir=#{manifest_dir}"
              command += " --handoff-dir=#{handoff_dir}" unless handoff_dir.to_s.empty?
              command += " #{draft[:path]}"
            end
            actions << next_action(
              :generate_provider_manifest,
              "generate the #{provider_key} provider manifest for #{label}",
              provider: provider_key,
              path: manifest[:path],
              command: command
            )
          end
          if report[:exists]
            if report[:fresh] == false
              actions << next_action(
                :refresh_manifest_review_report,
                "refresh the #{provider_key} manifest-review report for #{label}",
                provider: provider_key,
                path: report[:path],
                command: manifest_review_refresh_command(provider_key, manifest[:path], report[:path], handoff_dir)
              )
              next
            end
            next unless report[:valid] == false

            actions << next_action(
              :resolve_manifest_review_findings,
              "resolve the #{provider_key} manifest-review findings for #{label}",
              provider: provider_key,
              path: report[:path],
              command: provider[:manifest_review_command]
            )
          else
            command = nil
            unless manifest[:path].to_s.empty?
              command = "rules-ctl manifest-review --provider=#{provider_key} --manifest=#{manifest[:path]}"
              command += " --handoff-dir=#{handoff_dir}" unless handoff_dir.to_s.empty?
              command += " --output=#{report[:path]}"
            end
            actions << next_action(
              :write_manifest_review_report,
              "write the #{provider_key} manifest-review report for #{label}",
              provider: provider_key,
              path: report[:path],
              command: command
            )
          end
        end

        actions
      end

      def next_action(code, message, provider: nil, path: nil, command: nil)
        {
          code: code,
          provider: provider,
          message: message,
          path: path,
          command: command
        }.compact
      end

      def scope_status(entry, missing, provider_artifacts)
        return 'failed' if entry[:status].to_s != 'ok'
        return 'partial' unless missing.empty?
        return 'partial' if provider_artifacts_with_stale_reports?(provider_artifacts)
        return 'partial' if provider_artifacts_with_invalid_reports?(provider_artifacts)

        'complete'
      end

      def provider_artifacts_with_stale_reports?(provider_artifacts)
        provider_artifacts.any? { |provider| provider.dig(:manifest_review_report, :fresh) == false }
      end

      def provider_artifacts_with_invalid_reports?(provider_artifacts)
        provider_artifacts.any? { |provider| provider.dig(:manifest_review_report, :valid) == false }
      end

      def summary(scopes)
        {
          total_scopes: scopes.length,
          complete_scopes: scopes.count { |scope| scope[:status] == 'complete' },
          partial_scopes: scopes.count { |scope| scope[:status] == 'partial' },
          failed_scopes: scopes.count { |scope| scope[:status] == 'failed' },
          missing_artifact_count: scopes.sum { |scope| Array(scope[:missing_artifacts]).length },
          next_action_counts: next_action_counts(scopes),
          reviewed_handoffs: scopes.count { |scope| scope.dig(:handoff, :review_status) == 'reviewed' },
          draft_files: scopes.count { |scope| scope.dig(:draft, :exists) },
          provider_manifest_files: scopes.sum { |scope| scope.fetch(:providers).count { |provider| provider.dig(:manifest, :exists) } },
          manifest_review_reports: scopes.sum { |scope| scope.fetch(:providers).count { |provider| provider.dig(:manifest_review_report, :exists) } },
          fresh_manifest_review_reports: scopes.sum { |scope| scope.fetch(:providers).count { |provider| provider.dig(:manifest_review_report, :fresh) == true } },
          stale_manifest_review_reports: scopes.sum { |scope| scope.fetch(:providers).count { |provider| provider.dig(:manifest_review_report, :fresh) == false } },
          valid_manifest_review_reports: scopes.sum { |scope| scope.fetch(:providers).count { |provider| provider.dig(:manifest_review_report, :valid) == true } },
          invalid_manifest_review_reports: scopes.sum { |scope| scope.fetch(:providers).count { |provider| provider.dig(:manifest_review_report, :valid) == false } }
        }
      end

      def next_action_counts(scopes)
        counts = Hash.new(0)
        scopes.each do |scope|
          Array(scope[:next_actions]).each do |action|
            counts[action.fetch(:code)] += 1
          end
        end
        counts
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
