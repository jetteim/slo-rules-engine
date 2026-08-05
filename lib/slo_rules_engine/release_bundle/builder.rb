# frozen_string_literal: true

require 'json'
require 'time'

module SloRulesEngine
  module ReleaseBundle
    class Builder
      def build(artifact_index_path, reviewer:, reviewed_at:, plans: {}, sloth_evidence: {})
        @artifacts = {}
        @findings = []
        @index_path = File.expand_path(artifact_index_path)
        @index = parse_json(@index_path, kind: 'onboarding_artifact_index')
        reviewed_at = normalize_timestamp(reviewed_at)

        add_artifact(
          uid: 'onboarding-artifact-index',
          kind: 'onboarding_artifact_index',
          path: @index_path,
          content: @index
        )
        add_discovery_index

        scopes = Array(fetch_value(@index, :scopes)).map { |scope| package_scope(scope) }
        targets = scopes.flat_map { |scope| scope.delete(:targets) }.compact
        attach_plans(targets, plans)
        attach_sloth_evidence(targets, sloth_evidence)
        validate_manifest_reviews(targets)

        review = {
          reviewer: reviewer.to_s,
          reviewed_at: reviewed_at,
          scopes: scopes.map { |scope| scope.fetch(:review) }.sort_by { |scope| scope.fetch(:label) }
        }
        lifecycle = lifecycle_for(targets)
        artifacts = @artifacts.values.sort_by { |artifact| artifact.fetch(:uid) }
        bundle = {
          schema_version: SCHEMA_VERSION,
          kind: KIND,
          bundle_id: nil,
          lifecycle: lifecycle,
          review: review,
          targets: targets.sort_by { |target| target.fetch(:uid) },
          artifacts: artifacts,
          findings: @findings,
          summary: summary(scopes, targets, artifacts)
        }
        bundle[:bundle_id] = Fingerprint.bundle_id(bundle)
        SchemaValidator.validate!(bundle)
      end

      private

      def add_discovery_index
        path = fetch_value(fetch_value(@index, :artifact_index), :discovery_index)
        add_artifact(
          uid: 'discovery-index',
          kind: 'discovery_index',
          path: path
        )
      end

      def package_scope(scope)
        label = fetch_value(scope, :label).to_s
        discovery_uid = add_artifact(
          uid: "discovery:#{label}",
          kind: 'discovery_evidence',
          path: fetch_value(fetch_value(scope, :discovery), :path),
          scope: label
        )
        handoff_uid = add_artifact(
          uid: "handoff:#{label}",
          kind: 'reviewed_handoff',
          path: fetch_value(fetch_value(scope, :handoff), :path),
          scope: label
        )
        definition_uid = add_artifact(
          uid: "definition:#{label}",
          kind: 'reviewed_definition',
          path: fetch_value(fetch_value(scope, :draft), :path),
          scope: label,
          content_type: 'text/x-ruby'
        )
        handoff = artifact_content(handoff_uid)
        review = review_entry(label, handoff, handoff_uid)

        targets = Array(fetch_value(scope, :providers)).map do |provider|
          package_target(scope, provider)
        end

        {
          label: label,
          discovery_artifact_uid: discovery_uid,
          handoff_artifact_uid: handoff_uid,
          reviewed_definition_artifact_uid: definition_uid,
          review: review,
          targets: targets
        }
      end

      def review_entry(label, handoff, handoff_uid)
        review = fetch_value(handoff, :review)
        unless review.is_a?(Hash) && fetch_value(review, :status) == 'reviewed'
          add_finding(
            'unreviewed_handoff',
            "scopes[#{label}].handoff",
            'handoff packet must be reviewed before release bundling'
          )
          review ||= {}
        end
        accepted = Array(fetch_value(review, :accepted_candidate_uids)).map(&:to_s).sort
        if accepted.empty?
          add_finding(
            'missing_accepted_candidates',
            "scopes[#{label}].handoff.review.accepted_candidate_uids",
            'reviewed handoff must include at least one accepted candidate'
          )
        end
        {
          label: label,
          status: 'reviewed',
          handoff_artifact_uid: handoff_uid,
          accepted_candidate_uids: accepted,
          rejected_candidate_uids: Array(fetch_value(review, :rejected_candidate_uids)).map(&:to_s).sort,
          notes: Array(fetch_value(review, :notes)).map(&:to_s)
        }
      end

      def package_target(scope, provider_entry)
        label = fetch_value(scope, :label).to_s
        service = fetch_value(fetch_value(scope, :scope), :service).to_s
        provider = fetch_value(provider_entry, :provider).to_s
        manifest_path = fetch_value(fetch_value(provider_entry, :manifest), :path)
        report_path = fetch_value(fetch_value(provider_entry, :manifest_review_report), :path)
        manifest_uid = add_artifact(
          uid: "manifest:#{service}:#{provider}",
          kind: 'provider_manifest',
          path: manifest_path,
          scope: label,
          provider: provider
        )
        report_uid = add_artifact(
          uid: "manifest-review:#{provider}",
          kind: 'manifest_review_report',
          path: report_path,
          provider: provider
        )
        automation_mode = begin
          SloRulesEngine.default_provider_registry.fetch(provider).automation_mode
        rescue KeyError
          add_finding('unknown_provider_target', "targets[#{service}/#{provider}]", "unknown provider #{provider.inspect}")
          'unknown'
        end
        {
          uid: "#{service}/#{provider}",
          scope: label,
          service: service,
          provider: provider,
          automation_mode: automation_mode,
          manifest_artifact_uid: manifest_uid,
          review_report_artifact_uid: report_uid
        }
      end

      def attach_plans(targets, plans)
        normalized_plans = plans.to_h { |target, path| [target.to_s, path] }
        normalized_plans.each_key do |target_uid|
          next if targets.any? { |target| target[:uid] == target_uid }

          add_finding('unknown_plan_target', "plans[#{target_uid}]", 'change plan target is not in the artifact index')
        end

        targets.each do |target|
          path = normalized_plans[target.fetch(:uid)]
          next unless path

          plan = parse_json(path, kind: 'change_plan')
          plan = plan.fetch(0) if plan.is_a?(Array) && plan.length == 1
          unless valid_plan?(plan, target)
            add_finding(
              'invalid_change_plan',
              "plans[#{target.fetch(:uid)}]",
              'change plan must be one dry-run plan for the target provider'
            )
            next
          end
          uid = add_artifact(
            uid: "change-plan:#{target.fetch(:uid)}",
            kind: 'change_plan',
            path: path,
            scope: target.fetch(:scope),
            provider: target.fetch(:provider),
            content: plan
          )
          target[:change_plan_artifact_uid] = uid
        end
      end

      def valid_plan?(plan, target)
        plan.is_a?(Hash) &&
          fetch_value(plan, :provider) == target.fetch(:provider) &&
          fetch_value(plan, :mode) == 'dry_run' &&
          fetch_value(plan, :operations).is_a?(Array) &&
          fetch_value(plan, :summary).is_a?(Hash)
      end

      def attach_sloth_evidence(targets, evidence_paths)
        evidence_paths = evidence_paths.to_h { |target, path| [target.to_s, path] }
        evidence_paths.each_key do |target_uid|
          next if targets.any? { |target| target.fetch(:uid) == target_uid }

          add_finding(
            'unknown_sloth_evidence_target',
            "sloth_evidence[#{target_uid}]",
            'Sloth downstream evidence target is not in the artifact index'
          )
        end

        targets.each do |target|
          target_uid = target.fetch(:uid)
          path = evidence_paths[target_uid]
          next unless path

          unless target.fetch(:provider) == 'sloth'
            add_finding(
              'invalid_sloth_evidence_target',
              "sloth_evidence[#{target_uid}]",
              'Sloth downstream evidence can only be attached to a Sloth target'
            )
            next
          end

          manifest = artifact_content(target.fetch(:manifest_artifact_uid))
          begin
            SloRulesEngine::LiveStatus::SlothReader.new.preflight(
              manifest,
              evidence_path: path
            )
          rescue SloRulesEngine::Sloth::DownstreamEvidence::ContractError => error
            @findings.concat(error.findings.map do |finding|
              normalize_evidence_finding(finding, target_uid)
            end)
            next
          end

          uid = add_artifact(
            uid: "sloth-evidence:#{target_uid}",
            kind: 'sloth_downstream_evidence',
            path: path,
            scope: target.fetch(:scope),
            provider: 'sloth'
          )
          target[:downstream_evidence_artifact_uid] = uid if uid
        end
      end

      def normalize_evidence_finding(finding, target_uid)
        finding.to_h.each_with_object({}) do |(key, value), normalized|
          normalized[key.to_sym] = value
        end.merge(target_uid: target_uid)
      end

      def validate_manifest_reviews(targets)
        handoff_dir = fetch_value(fetch_value(@index, :artifact_index), :handoff_dir)
        targets.group_by { |target| target.fetch(:provider) }.each do |provider, provider_targets|
          manifests = provider_targets.map do |target|
            artifact_content(target.fetch(:manifest_artifact_uid))
          end.compact
          report_uid = provider_targets.map { |target| target.fetch(:review_report_artifact_uid) }.compact.first
          saved_report = artifact_content(report_uid)
          next if manifests.empty? || saved_report.nil?

          current_report = SloRulesEngine::ManifestReviewQueue::ReportBuilder.new.build(
            manifests,
            provider: provider,
            handoff_dir: handoff_dir
          )
          unless current_report[:valid] && fetch_value(saved_report, :valid) == true
            add_finding(
              'invalid_manifest_review_report',
              "targets[#{provider}].manifest_review_report",
              'manifest-review report is not apply-ready'
            )
          end
          freshness = SloRulesEngine::ManifestReviewQueue::FreshnessValidator.new.validate(
            saved_report,
            current_report
          )
          Array(freshness[:findings]).each { |finding| @findings << finding }
        end
      end

      def add_artifact(uid:, kind:, path:, scope: nil, provider: nil, content_type: 'application/json', content: nil)
        return uid if @artifacts.key?(uid)
        if path.to_s.empty? || !File.exist?(path)
          add_finding('missing_source_artifact', "artifacts.#{kind}", "source artifact does not exist at #{path}")
          return nil
        end

        content ||= content_type == 'text/x-ruby' ? File.read(path) : parse_json(path, kind: kind)
        credential_paths = CredentialScanner.paths(content, "artifacts.#{kind}.content")
        raise CredentialError, credential_paths unless credential_paths.empty?

        fingerprint = content_type == 'text/x-ruby' ? Fingerprint.text(content) : Fingerprint.content(content)
        @artifacts[uid] = {
          uid: uid,
          kind: kind,
          scope: scope,
          provider: provider,
          content_type: content_type,
          fingerprint: fingerprint,
          source: {
            type: 'file',
            path: File.expand_path(path)
          },
          content: content
        }.compact
        uid
      end

      def artifact_content(uid)
        return nil unless uid

        @artifacts.dig(uid, :content)
      end

      def parse_json(path, kind:)
        JSON.parse(File.read(path))
      rescue JSON::ParserError => error
        add_finding('invalid_json_artifact', "artifacts.#{kind}", error.message)
        {}
      end

      def normalize_timestamp(value)
        Time.iso8601(value.to_s).utc.iso8601
      rescue ArgumentError
        raise ArgumentError, 'reviewed_at must be an ISO 8601 timestamp'
      end

      def lifecycle_for(targets)
        codes = @findings.map { |finding| finding[:code].to_s }
        return 'stale' if codes.any? { |code| code.start_with?('stale_') }
        return 'incomplete' unless codes.empty?
        return 'apply_ready' if !targets.empty? && targets.all? { |target| target[:change_plan_artifact_uid] }

        'review_ready'
      end

      def summary(scopes, targets, artifacts)
        SummaryBuilder.new.build(
          review: { scopes: scopes.map { |scope| scope.fetch(:review) } },
          targets: targets,
          artifacts: artifacts,
          findings: @findings
        )
      end

      def add_finding(code, path, message)
        @findings << {
          code: code,
          path: path,
          message: message
        }
      end

      def fetch_value(container, key)
        return container[key] if container.is_a?(Hash) && container.key?(key)
        return container[key.to_s] if container.is_a?(Hash) && container.key?(key.to_s)

        nil
      end
    end
  end
end
