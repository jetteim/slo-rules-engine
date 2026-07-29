# frozen_string_literal: true

require 'time'

module SloRulesEngine
  module ReleaseBundle
    SCHEMA_VERSION = 'slo-rules-engine/release-bundle/v1'
    KIND = 'SLOReleaseBundle'
    EXECUTION_SCHEMA_VERSION = 'slo-rules-engine/bundle-target-execution/v1' unless const_defined?(:EXECUTION_SCHEMA_VERSION)
    VERIFICATION_SCHEMA_VERSION = 'slo-rules-engine/bundle-target-verification/v1' unless const_defined?(:VERIFICATION_SCHEMA_VERSION)
    LIFECYCLE_STATES = %w[incomplete review_ready apply_ready stale applied verified].freeze
    ARTIFACT_KINDS = %w[
      onboarding_artifact_index
      discovery_index
      discovery_evidence
      reviewed_handoff
      reviewed_definition
      provider_manifest
      manifest_review_report
      change_plan
      execution_result
      target_verification
    ].freeze

    class SchemaError < StandardError
      attr_reader :result

      def initialize(result)
        @result = result
        super('release bundle does not match schema')
      end
    end

    class CredentialError < StandardError
      attr_reader :paths

      def initialize(paths)
        @paths = paths
        super("release bundle contains forbidden credential-like keys at #{paths.join(', ')}")
      end
    end

    module CredentialScanner
      FORBIDDEN_KEY = /\A(?:api[_-]?key|app[_-]?key|access[_-]?key|secret|password|token|authorization|credential|credentials)\z/i

      module_function

      def paths(value, path)
        case value
        when Hash
          value.flat_map do |key, entry|
            key_path = "#{path}.#{key}"
            matches = key.to_s.match?(FORBIDDEN_KEY) ? [key_path] : []
            matches + paths(entry, key_path)
          end
        when Array
          value.each_with_index.flat_map { |entry, index| paths(entry, "#{path}[#{index}]") }
        else
          []
        end
      end
    end

    module SchemaValidator
      module_function

      def validate(bundle)
        result = ValidationResult.new
        validate_exact(result, 'schema_version', fetch_value(bundle, :schema_version), SCHEMA_VERSION)
        validate_exact(result, 'kind', fetch_value(bundle, :kind), KIND)

        bundle_id = fetch_value(bundle, :bundle_id)
        unless bundle_id.to_s.match?(/\Aslo-bundle-[0-9a-f]{64}\z/)
          result.error('bundle_id', 'must be a content-addressed slo-bundle identifier')
        end

        lifecycle = fetch_value(bundle, :lifecycle)
        result.error('lifecycle', "must be one of #{LIFECYCLE_STATES.inspect}") unless LIFECYCLE_STATES.include?(lifecycle)

        validate_review(result, fetch_value(bundle, :review))
        validate_transition(
          result,
          fetch_value(bundle, :transition),
          lifecycle: lifecycle
        ) if fetch_value(bundle, :transition)
        artifacts = validate_array(result, 'artifacts', fetch_value(bundle, :artifacts))
        targets = validate_array(result, 'targets', fetch_value(bundle, :targets))
        validate_artifacts(result, artifacts)
        validate_targets(
          result,
          targets,
          artifacts,
          require_references: lifecycle != 'incomplete',
          require_plans: %w[apply_ready applied verified].include?(lifecycle),
          require_executions: %w[applied verified].include?(lifecycle),
          require_verifications: lifecycle == 'verified'
        )
        validate_array(result, 'findings', fetch_value(bundle, :findings))
        validate_hash(result, 'summary', fetch_value(bundle, :summary))

        CredentialScanner.paths(bundle, 'bundle').each do |path|
          result.error(path, 'credential-like keys are forbidden in release bundles')
        end
        result
      end

      def validate_transition(result, transition, lifecycle:)
        validate_hash(result, 'transition', transition)
        return unless transition.is_a?(Hash)

        action = fetch_value(transition, :action)
        unless %w[plan apply verify].include?(action)
          result.error('transition.action', 'must be plan, apply, or verify')
          return
        end
        predecessor_id = fetch_value(transition, :predecessor_bundle_id)
        unless predecessor_id.to_s.match?(/\Aslo-bundle-[0-9a-f]{64}\z/)
          result.error('transition.predecessor_bundle_id', 'must be a content-addressed slo-bundle identifier')
        end
        predecessor_lifecycle = {
          'plan' => 'review_ready',
          'apply' => 'apply_ready',
          'verify' => 'applied'
        }.fetch(action)
        validate_exact(result, 'transition.predecessor_lifecycle', fetch_value(transition, :predecessor_lifecycle), predecessor_lifecycle)
        expected_lifecycle = {
          'plan' => 'apply_ready',
          'apply' => 'applied',
          'verify' => 'verified'
        }.fetch(action)
        validate_exact(result, 'lifecycle', lifecycle, expected_lifecycle)
      end

      def validate!(bundle)
        result = validate(bundle)
        raise SchemaError, result unless result.valid?

        bundle
      end

      def validate_review(result, review)
        validate_hash(result, 'review', review)
        return unless review.is_a?(Hash)

        validate_presence(result, 'review.reviewer', fetch_value(review, :reviewer))
        reviewed_at = fetch_value(review, :reviewed_at)
        validate_presence(result, 'review.reviewed_at', reviewed_at)
        begin
          Time.iso8601(reviewed_at.to_s) unless reviewed_at.to_s.empty?
        rescue ArgumentError
          result.error('review.reviewed_at', 'must be an ISO 8601 timestamp')
        end
        scopes = validate_array(result, 'review.scopes', fetch_value(review, :scopes))
        scopes.each_with_index do |scope, index|
          path = "review.scopes[#{index}]"
          validate_presence(result, "#{path}.label", fetch_value(scope, :label))
          validate_exact(result, "#{path}.status", fetch_value(scope, :status), 'reviewed')
          validate_array(result, "#{path}.accepted_candidate_uids", fetch_value(scope, :accepted_candidate_uids))
          validate_array(result, "#{path}.rejected_candidate_uids", fetch_value(scope, :rejected_candidate_uids))
          validate_array(result, "#{path}.notes", fetch_value(scope, :notes))
        end
      end

      def validate_artifacts(result, artifacts)
        result.error('artifacts', 'must contain at least one artifact') if artifacts.empty?
        seen = {}
        artifacts.each_with_index do |artifact, index|
          path = "artifacts[#{index}]"
          validate_hash(result, path, artifact)
          next unless artifact.is_a?(Hash)

          uid = fetch_value(artifact, :uid)
          validate_presence(result, "#{path}.uid", uid)
          result.error("#{path}.uid", 'must be unique') if seen[uid]
          seen[uid] = true unless uid.to_s.empty?

          kind = fetch_value(artifact, :kind)
          result.error("#{path}.kind", "must be one of #{ARTIFACT_KINDS.inspect}") unless ARTIFACT_KINDS.include?(kind)
          fingerprint = fetch_value(artifact, :fingerprint)
          result.error("#{path}.fingerprint", 'must be a SHA-256 fingerprint') unless fingerprint.to_s.match?(/\A[0-9a-f]{64}\z/)
          content_type = fetch_value(artifact, :content_type)
          unless %w[application/json text/x-ruby].include?(content_type)
            result.error("#{path}.content_type", 'must be application/json or text/x-ruby')
          end
          result.error("#{path}.content", 'is required') if fetch_value(artifact, :content).nil?
          source = fetch_value(artifact, :source)
          validate_hash(result, "#{path}.source", source)
          validate_artifact_source(result, "#{path}.source", source) if source.is_a?(Hash)
        end
      end

      def validate_artifact_source(result, path, source)
        type = fetch_value(source, :type) || 'file'
        case type
        when 'file'
          validate_presence(result, "#{path}.path", fetch_value(source, :path))
        when 'generated'
          predecessor_id = fetch_value(source, :predecessor_bundle_id)
          unless predecessor_id.to_s.match?(/\Aslo-bundle-[0-9a-f]{64}\z/)
            result.error("#{path}.predecessor_bundle_id", 'must be a content-addressed slo-bundle identifier')
          end
          validate_presence(result, "#{path}.target_uid", fetch_value(source, :target_uid))
        else
          result.error("#{path}.type", 'must be file or generated')
        end
      end

      def validate_targets(
        result,
        targets,
        artifacts,
        require_references:,
        require_plans:,
        require_executions:,
        require_verifications:
      )
        result.error('targets', 'must contain at least one provider target') if targets.empty?
        artifact_uids = artifacts.to_h { |artifact| [fetch_value(artifact, :uid), artifact] }
        seen = {}
        targets.each_with_index do |target, index|
          path = "targets[#{index}]"
          uid = fetch_value(target, :uid)
          validate_presence(result, "#{path}.uid", uid)
          result.error("#{path}.uid", 'must be unique') if seen[uid]
          seen[uid] = true unless uid.to_s.empty?
          validate_presence(result, "#{path}.service", fetch_value(target, :service))
          validate_presence(result, "#{path}.provider", fetch_value(target, :provider))
          validate_presence(result, "#{path}.automation_mode", fetch_value(target, :automation_mode))
          provider = fetch_value(target, :provider)
          {
            manifest_artifact_uid: 'provider_manifest',
            review_report_artifact_uid: 'manifest_review_report'
          }.each do |reference, expected_kind|
            reference_uid = fetch_value(target, reference)
            next unless require_references || reference_uid

            validate_artifact_reference(
              result,
              "#{path}.#{reference}",
              reference_uid,
              artifact_uids,
              expected_kind: expected_kind,
              expected_provider: provider
            )
          end
          plan_uid = fetch_value(target, :change_plan_artifact_uid)
          if require_plans || plan_uid
            validate_artifact_reference(
              result,
              "#{path}.change_plan_artifact_uid",
              plan_uid,
              artifact_uids,
              expected_kind: 'change_plan',
              expected_provider: provider
            )
          end
          execution_uid = fetch_value(target, :execution_artifact_uid)
          next unless require_executions || execution_uid

          execution = validate_artifact_reference(
            result,
            "#{path}.execution_artifact_uid",
            execution_uid,
            artifact_uids,
            expected_kind: 'execution_result',
            expected_provider: provider
          )
          validate_execution_reference(result, path, target, execution) if execution

          verification_uid = fetch_value(target, :verification_artifact_uid)
          next unless require_verifications || verification_uid

          verification = validate_artifact_reference(
            result,
            "#{path}.verification_artifact_uid",
            verification_uid,
            artifact_uids,
            expected_kind: 'target_verification',
            expected_provider: provider
          )
          validate_verification_reference(result, path, target, verification) if verification
        end
      end

      def validate_artifact_reference(result, path, uid, artifacts, expected_kind:, expected_provider:)
        validate_presence(result, path, uid)
        return if uid.to_s.empty?

        artifact = artifacts[uid]
        unless artifact
          result.error(path, 'must reference a packaged artifact')
          return
        end
        unless fetch_value(artifact, :kind) == expected_kind
          result.error(path, "must reference a #{expected_kind} artifact")
        end
        unless fetch_value(artifact, :provider) == expected_provider
          result.error(path, 'must reference an artifact for the target provider')
        end
        artifact
      end

      def validate_execution_reference(result, path, target, artifact)
        content = fetch_value(artifact, :content)
        unless content.is_a?(Hash)
          result.error("#{path}.execution_artifact_uid", 'must reference an execution result object')
          return
        end
        validate_exact(
          result,
          "#{path}.execution.target_uid",
          fetch_value(content, :target_uid),
          fetch_value(target, :uid)
        )
        validate_exact(
          result,
          "#{path}.execution.schema_version",
          fetch_value(content, :schema_version),
          EXECUTION_SCHEMA_VERSION
        )
        validate_exact(
          result,
          "#{path}.execution.kind",
          fetch_value(content, :kind),
          'BundleTargetExecution'
        )
        {
          target_uid: :uid,
          service: :service,
          provider: :provider
        }.each do |content_key, target_key|
          validate_exact(
            result,
            "#{path}.execution.#{content_key}",
            fetch_value(content, content_key),
            fetch_value(target, target_key)
          )
        end
        approved_plan = fetch_value(content, :approved_plan)
        validate_hash(result, "#{path}.execution.approved_plan", approved_plan)
        validate_presence(
          result,
          "#{path}.execution.approved_plan.approved_plan_id",
          fetch_value(approved_plan, :approved_plan_id)
        )
        runtime = fetch_value(content, :runtime)
        validate_hash(result, "#{path}.execution.runtime", runtime)
        validate_presence(
          result,
          "#{path}.execution.runtime.output_dir",
          fetch_value(runtime, :output_dir)
        )
        operation_journal = fetch_value(content, :operation_journal)
        validate_hash(result, "#{path}.execution.operation_journal", operation_journal)
        %i[journal_id path status fingerprint].each do |key|
          validate_presence(
            result,
            "#{path}.execution.operation_journal.#{key}",
            fetch_value(operation_journal, key)
          )
        end
        fingerprint = fetch_value(operation_journal, :fingerprint)
        unless fingerprint.to_s.match?(/\A[0-9a-f]{64}\z/)
          result.error(
            "#{path}.execution.operation_journal.fingerprint",
            'must be a SHA-256 fingerprint'
          )
        end
        execution_result = fetch_value(content, :result)
        validate_hash(result, "#{path}.execution.result", execution_result)
        validate_exact(
          result,
          "#{path}.execution.result.provider",
          fetch_value(execution_result, :provider),
          fetch_value(target, :provider)
        )
        validate_exact(
          result,
          "#{path}.execution.result.service",
          fetch_value(execution_result, :service),
          fetch_value(target, :service)
        )
        status = fetch_value(execution_result, :status)
        unless %w[succeeded noop].include?(status)
          result.error("#{path}.execution.result.status", 'must be succeeded or noop')
        end
      end

      def validate_verification_reference(result, path, target, artifact)
        content = fetch_value(artifact, :content)
        unless content.is_a?(Hash)
          result.error("#{path}.verification_artifact_uid", 'must reference a target verification object')
          return
        end
        {
          schema_version: VERIFICATION_SCHEMA_VERSION,
          kind: 'BundleTargetVerification',
          target_uid: fetch_value(target, :uid),
          service: fetch_value(target, :service),
          provider: fetch_value(target, :provider),
          status: 'succeeded'
        }.each do |key, expected|
          validate_exact(
            result,
            "#{path}.verification.#{key}",
            fetch_value(content, key),
            expected
          )
        end
        validate_presence(
          result,
          "#{path}.verification.checked_at",
          fetch_value(content, :checked_at)
        )
        verification = fetch_value(content, :verification)
        validate_hash(result, "#{path}.verification.verification", verification)
        return unless verification.is_a?(Hash)

        validate_exact(
          result,
          "#{path}.verification.verification.engine_owned_status",
          fetch_value(verification, :engine_owned_status),
          'succeeded'
        )
        unless %w[succeeded pending].include?(fetch_value(verification, :status))
          result.error(
            "#{path}.verification.verification.status",
            'must be succeeded or pending'
          )
        end
        unless %w[succeeded pending not_required].include?(fetch_value(verification, :external_status))
          result.error(
            "#{path}.verification.verification.external_status",
            'must be succeeded, pending, or not_required'
          )
        end
        validate_array(
          result,
          "#{path}.verification.verification.resources",
          fetch_value(verification, :resources)
        )
      end

      def validate_array(result, path, value)
        unless value.is_a?(Array)
          result.error(path, 'must be an array')
          return []
        end

        value
      end

      def validate_hash(result, path, value)
        result.error(path, 'must be a hash') unless value.is_a?(Hash)
      end

      def validate_presence(result, path, value)
        result.error(path, 'is required') if value.nil? || (value.respond_to?(:empty?) && value.empty?)
      end

      def validate_exact(result, path, value, expected)
        result.error(path, "must equal #{expected.inspect}") unless value == expected
      end

      def fetch_value(container, key)
        return container[key] if container.is_a?(Hash) && container.key?(key)
        return container[key.to_s] if container.is_a?(Hash) && container.key?(key.to_s)

        nil
      end
    end
  end
end
