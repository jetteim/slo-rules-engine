# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'tempfile'
require 'time'

module SloRulesEngine
  module ProviderState
    module ApprovedPlan
      SCHEMA_VERSION = 'slo-rules-engine/approved-provider-plan/v1'
      KIND = 'ApprovedProviderPlan'
      SUPPORTED_AUTOMATION_MODES = %w[manifest_bundle external_generator].freeze

      class Error < StandardError
        attr_reader :code, :path, :findings

        def initialize(code, message, path: nil, findings: [])
          @code = code
          @path = path
          @findings = findings
          super(message)
        end
      end

      class OutputConflict < Error
        def initialize(path)
          super(
            'approved_plan_output_conflict',
            "approved plan output already exists with different content at #{path}",
            path: path
          )
        end
      end

      class Document
        attr_reader :approved_plan_id, :target, :source_bundle, :approval,
                    :evidence, :runtime, :provider_plan

        def initialize(payload:, provider_plan:)
          @payload = Value.immutable(payload)
          @approved_plan_id = Value.fetch(payload, :approved_plan_id).to_s.freeze
          @target = Value.immutable(Value.fetch(payload, :target))
          @source_bundle = Value.immutable(Value.fetch(payload, :source_bundle))
          @approval = Value.immutable(Value.fetch(payload, :approval))
          @evidence = Value.immutable(Value.fetch(payload, :evidence))
          @runtime = Value.immutable(Value.fetch(payload, :runtime))
          @provider_plan = provider_plan
          freeze
        end

        def to_h
          Value.copy(@payload)
        end

        def reference
          {
            schema_version: SCHEMA_VERSION,
            kind: 'ApprovedProviderPlanReference',
            approved_plan_id: approved_plan_id,
            provider_plan_fingerprint: provider_plan.fingerprint,
            source_bundle_id: Value.fetch(source_bundle, :bundle_id),
            evidence_fingerprint: Fingerprint.content(evidence)
          }
        end
      end

      class Builder
        def initialize(status_evaluator: ReleaseBundle::StatusEvaluator.new)
          @status_evaluator = status_evaluator
        end

        def build(bundle, target_uid:, reviewer:, reviewed_at:, notes: [])
          target = find_target!(bundle, target_uid)
          validate_automation_mode!(target)
          validate_bundle!(bundle)
          reviewer = require_presence!('approval.reviewer', reviewer)
          reviewed_at = normalize_timestamp(reviewed_at)
          notes = Array(notes).map(&:to_s)
          artifacts = artifacts_by_uid(bundle)
          provider_plan_artifact = artifact!(
            artifacts,
            Value.fetch(target, :change_plan_artifact_uid),
            'change_plan'
          )
          provider_plan = load_provider_plan(provider_plan_artifact)
          validate_plan_target!(provider_plan, target)
          manifest_artifact = artifact!(
            artifacts,
            Value.fetch(target, :manifest_artifact_uid),
            'provider_manifest'
          )
          review_report_artifact = artifact!(
            artifacts,
            Value.fetch(target, :review_report_artifact_uid),
            'manifest_review_report'
          )
          handoff_artifact = handoff_artifact!(bundle, target, artifacts)
          runtime = runtime_for(provider_plan, target)

          identity = {
            schema_version: SCHEMA_VERSION,
            kind: KIND,
            target: target_identity(target),
            source_bundle: {
              bundle_id: Value.fetch(bundle, :bundle_id),
              lifecycle: 'apply_ready'
            },
            approval: {
              reviewer: reviewer,
              reviewed_at: reviewed_at,
              notes: notes
            },
            evidence: {
              bundle_review_fingerprint: Fingerprint.content(Value.fetch(bundle, :review)),
              bundle_review: Value.copy(Value.fetch(bundle, :review)),
              change_plan: artifact_reference(provider_plan_artifact).merge(
                provider_plan_fingerprint: provider_plan.fingerprint
              ),
              provider_manifest: artifact_reference(manifest_artifact),
              manifest_review_report: artifact_reference(review_report_artifact),
              reviewed_handoff: artifact_reference(handoff_artifact)
            },
            runtime: runtime,
            provider_plan: provider_plan.to_h
          }
          credential_paths = CredentialScanner.paths(identity, 'approved_plan')
          unless credential_paths.empty?
            raise Error.new(
              'credential_material_forbidden',
              'approved plan contains credential-like keys',
              path: credential_paths.first
            )
          end

          identity[:approved_plan_id] = approved_plan_id(identity)
          Loader.new.load(identity).to_h
        end

        private

        def validate_bundle!(bundle)
          status = @status_evaluator.evaluate(bundle)
          return if status[:valid] && status[:effective_lifecycle] == 'apply_ready'

          code = status[:effective_lifecycle] == 'stale' ? 'stale_source_bundle' : 'invalid_source_bundle'
          raise Error.new(
            code,
            "plan approval requires a valid apply_ready bundle; effective lifecycle is " \
              "#{status[:effective_lifecycle].inspect}",
            findings: status[:findings]
          )
        end

        def find_target!(bundle, target_uid)
          target = Array(Value.fetch(bundle, :targets)).find do |candidate|
            Value.fetch(candidate, :uid).to_s == target_uid.to_s
          end
          return target if target

          raise Error.new(
            'unknown_plan_target',
            "target #{target_uid.inspect} is not present in the release bundle",
            path: 'target.uid'
          )
        end

        def validate_automation_mode!(target)
          mode = Value.fetch(target, :automation_mode).to_s
          return if SUPPORTED_AUTOMATION_MODES.include?(mode)

          raise Error.new(
            'unsupported_exact_plan_provider',
            "exact-plan execution does not support automation mode #{mode.inspect}",
            path: 'target.automation_mode'
          )
        end

        def artifacts_by_uid(bundle)
          Array(Value.fetch(bundle, :artifacts)).to_h do |artifact|
            [Value.fetch(artifact, :uid).to_s, artifact]
          end
        end

        def artifact!(artifacts, uid, kind)
          artifact = artifacts[uid.to_s]
          unless artifact && Value.fetch(artifact, :kind) == kind
            raise Error.new(
              'missing_approved_plan_evidence',
              "#{kind} artifact #{uid.inspect} is missing",
              path: "artifacts.#{uid}"
            )
          end
          artifact
        end

        def handoff_artifact!(bundle, target, artifacts)
          scope = Array(Value.fetch(Value.fetch(bundle, :review), :scopes)).find do |entry|
            Value.fetch(entry, :label).to_s == Value.fetch(target, :scope).to_s
          end
          uid = Value.fetch(scope, :handoff_artifact_uid)
          artifact!(artifacts, uid, 'reviewed_handoff')
        end

        def load_provider_plan(artifact)
          PlanLoader.new.load(Value.fetch(artifact, :content))
        rescue ContractError => error
          raise Error.new('invalid_provider_plan', error.message, path: error.path)
        end

        def validate_plan_target!(plan, target)
          return if plan.mode == 'dry_run' &&
                    plan.provider == Value.fetch(target, :provider).to_s &&
                    plan.service == Value.fetch(target, :service).to_s

          raise Error.new(
            'invalid_provider_plan',
            'change plan mode, provider, or service does not match the selected target',
            path: 'provider_plan'
          )
        end

        def runtime_for(plan, target)
          change = plan.changes.find { |entry| entry.target == 'manifest_file' }
          path = Value.fetch(change&.desired, :path)
          require_presence!('provider_plan.changes.manifest_file.desired.path', path)
          path = File.expand_path(path)
          expected_suffix = File.join(plan.service, plan.provider, 'manifest.json')
          unless path.end_with?(File.join(File::SEPARATOR, expected_suffix))
            raise Error.new(
              'invalid_provider_plan_runtime',
              'managed manifest path does not match the selected service and provider',
              path: 'provider_plan.changes.manifest_file.desired.path'
            )
          end
          output_dir = File.dirname(File.dirname(File.dirname(path)))
          validate_managed_paths!(plan, output_dir, target)
          { output_dir: output_dir }
        end

        def validate_managed_paths!(plan, output_dir, target)
          root = File.join(
            File.expand_path(output_dir),
            Value.fetch(target, :service).to_s,
            Value.fetch(target, :provider).to_s
          )
          prefix = "#{root}#{File::SEPARATOR}"
          plan.changes.each_with_index do |change, index|
            path = Value.fetch(change.desired, :path)
            next if path.nil?
            next if File.expand_path(path).start_with?(prefix)

            raise Error.new(
              'invalid_provider_plan_runtime',
              'managed operation path escapes the approved service/provider directory',
              path: "provider_plan.changes[#{index}].desired.path"
            )
          end
        end

        def target_identity(target)
          %i[uid scope service provider automation_mode].to_h do |key|
            [key, Value.fetch(target, key)]
          end
        end

        def artifact_reference(artifact)
          {
            artifact_uid: Value.fetch(artifact, :uid),
            fingerprint: Value.fetch(artifact, :fingerprint)
          }
        end

        def require_presence!(path, value)
          if value.nil? || (value.respond_to?(:empty?) && value.empty?)
            raise Error.new('invalid_approval_metadata', "#{path} is required", path: path)
          end

          value.to_s
        end

        def normalize_timestamp(value)
          Time.iso8601(value.to_s).utc.iso8601
        rescue ArgumentError
          raise Error.new(
            'invalid_approval_metadata',
            'approval.reviewed_at must be an ISO 8601 timestamp',
            path: 'approval.reviewed_at'
          )
        end

        def approved_plan_id(identity)
          "approved-provider-plan-#{Fingerprint.content(identity)}"
        end
      end

      class Loader
        EVIDENCE_KINDS = %i[
          change_plan
          provider_manifest
          manifest_review_report
          reviewed_handoff
        ].freeze

        def load(value)
          payload = deep_symbolize(value)
          require_hash!('approved_plan', payload)
          reject_credentials!(payload)
          require_equal!('schema_version', Value.fetch(payload, :schema_version), SCHEMA_VERSION)
          require_equal!('kind', Value.fetch(payload, :kind), KIND)
          validate_target!(Value.fetch(payload, :target))
          validate_source_bundle!(Value.fetch(payload, :source_bundle))
          validate_approval!(Value.fetch(payload, :approval))
          validate_evidence!(Value.fetch(payload, :evidence))
          provider_plan = load_provider_plan(Value.fetch(payload, :provider_plan))
          validate_plan_identity!(provider_plan, payload)
          validate_runtime!(Value.fetch(payload, :runtime), provider_plan)
          expected_id = "approved-provider-plan-#{Fingerprint.content(
            payload.reject { |key, _value| key == :approved_plan_id }
          )}"
          require_equal!('approved_plan_id', Value.fetch(payload, :approved_plan_id), expected_id)
          Document.new(payload: payload, provider_plan: provider_plan)
        end

        private

        def validate_target!(target)
          require_hash!('target', target)
          %i[uid scope service provider automation_mode].each do |key|
            required("target.#{key}", target, key)
          end
          mode = Value.fetch(target, :automation_mode).to_s
          unless SUPPORTED_AUTOMATION_MODES.include?(mode)
            raise Error.new(
              'unsupported_exact_plan_provider',
              "exact-plan execution does not support automation mode #{mode.inspect}",
              path: 'target.automation_mode'
            )
          end
        end

        def validate_source_bundle!(source_bundle)
          require_hash!('source_bundle', source_bundle)
          bundle_id = required('source_bundle.bundle_id', source_bundle, :bundle_id)
          unless bundle_id.to_s.match?(/\Aslo-bundle-[0-9a-f]{64}\z/)
            raise Error.new(
              'invalid_approved_plan',
              'source_bundle.bundle_id must be a content-addressed bundle identity',
              path: 'source_bundle.bundle_id'
            )
          end
          require_equal!(
            'source_bundle.lifecycle',
            Value.fetch(source_bundle, :lifecycle),
            'apply_ready'
          )
        end

        def validate_approval!(approval)
          require_hash!('approval', approval)
          required('approval.reviewer', approval, :reviewer)
          reviewed_at = required('approval.reviewed_at', approval, :reviewed_at)
          Time.iso8601(reviewed_at.to_s)
          notes = Value.fetch(approval, :notes)
          raise_invalid!('approval.notes', 'must be an array') unless notes.is_a?(Array)
        rescue ArgumentError
          raise_invalid!('approval.reviewed_at', 'must be an ISO 8601 timestamp')
        end

        def validate_evidence!(evidence)
          require_hash!('evidence', evidence)
          bundle_review = Value.fetch(evidence, :bundle_review)
          require_hash!('evidence.bundle_review', bundle_review)
          fingerprint = required(
            'evidence.bundle_review_fingerprint',
            evidence,
            :bundle_review_fingerprint
          )
          validate_fingerprint!('evidence.bundle_review_fingerprint', fingerprint)
          require_equal!(
            'evidence.bundle_review_fingerprint',
            fingerprint,
            Fingerprint.content(bundle_review)
          )
          EVIDENCE_KINDS.each do |kind|
            reference = Value.fetch(evidence, kind)
            require_hash!("evidence.#{kind}", reference)
            required("evidence.#{kind}.artifact_uid", reference, :artifact_uid)
            validate_fingerprint!(
              "evidence.#{kind}.fingerprint",
              required("evidence.#{kind}.fingerprint", reference, :fingerprint)
            )
          end
          validate_fingerprint!(
            'evidence.change_plan.provider_plan_fingerprint',
            required(
              'evidence.change_plan.provider_plan_fingerprint',
              Value.fetch(evidence, :change_plan),
              :provider_plan_fingerprint
            )
          )
        end

        def load_provider_plan(payload)
          PlanLoader.new.load(payload)
        rescue ContractError => error
          raise Error.new('invalid_provider_plan', error.message, path: error.path)
        end

        def validate_plan_identity!(plan, payload)
          target = Value.fetch(payload, :target)
          unless plan.mode == 'dry_run' &&
                 plan.provider == Value.fetch(target, :provider).to_s &&
                 plan.service == Value.fetch(target, :service).to_s
            raise_invalid!('provider_plan', 'mode, provider, and service must match the target')
          end
          require_equal!(
            'evidence.change_plan.provider_plan_fingerprint',
            Value.fetch(Value.fetch(Value.fetch(payload, :evidence), :change_plan), :provider_plan_fingerprint),
            plan.fingerprint
          )
        end

        def validate_runtime!(runtime, plan)
          require_hash!('runtime', runtime)
          output_dir = File.expand_path(required('runtime.output_dir', runtime, :output_dir))
          manifest_change = plan.changes.find { |change| change.target == 'manifest_file' }
          manifest_path = File.expand_path(
            required(
              'provider_plan.changes.manifest_file.desired.path',
              manifest_change&.desired || {},
              :path
            )
          )
          expected = File.join(output_dir, plan.service, plan.provider, 'manifest.json')
          require_equal!('runtime.output_dir', manifest_path, expected)
          prefix = "#{File.join(output_dir, plan.service, plan.provider)}#{File::SEPARATOR}"
          plan.changes.each_with_index do |change, index|
            path = Value.fetch(change.desired, :path)
            next if path.nil?
            next if File.expand_path(path).start_with?(prefix)

            raise_invalid!(
              "provider_plan.changes[#{index}].desired.path",
              'must remain below runtime.output_dir for the selected service/provider'
            )
          end
        end

        def reject_credentials!(payload)
          paths = CredentialScanner.paths(payload, 'approved_plan')
          return if paths.empty?

          raise Error.new(
            'credential_material_forbidden',
            'approved plan contains credential-like keys',
            path: paths.first
          )
        end

        def validate_fingerprint!(path, value)
          return if value.to_s.match?(/\A[0-9a-f]{64}\z/)

          raise_invalid!(path, 'must be a SHA-256 fingerprint')
        end

        def required(path, container, key)
          value = Value.fetch(container, key)
          return value unless value.nil? || (value.respond_to?(:empty?) && value.empty?)

          raise_invalid!(path, 'is required')
        end

        def require_hash!(path, value)
          return if value.is_a?(Hash)

          raise_invalid!(path, 'must be a hash')
        end

        def require_equal!(path, actual, expected)
          return if actual == expected

          raise_invalid!(path, "must equal #{expected.inspect}")
        end

        def raise_invalid!(path, message)
          raise Error.new('invalid_approved_plan', "#{path} #{message}", path: path)
        end

        def deep_symbolize(value)
          JSON.parse(JSON.generate(value), symbolize_names: true)
        rescue JSON::GeneratorError, JSON::ParserError => error
          raise Error.new('invalid_approved_plan', error.message, path: 'approved_plan')
        end
      end

      class StatusEvaluator
        def evaluate(value)
          document = Loader.new.load(value)
          {
            valid: true,
            status: 'approved',
            schema_version: SCHEMA_VERSION,
            approved_plan_id: document.approved_plan_id,
            target: Value.copy(document.target),
            source_bundle: Value.copy(document.source_bundle),
            approval: Value.copy(document.approval),
            runtime: Value.copy(document.runtime),
            provider_plan: {
              fingerprint: document.provider_plan.fingerprint,
              desired_state_fingerprint: document.provider_plan.desired_state.fingerprint,
              observed_state_fingerprint: document.provider_plan.observed_state.fingerprint,
              summary: Value.copy(document.provider_plan.summary)
            },
            findings: []
          }
        rescue Error => error
          {
            valid: false,
            status: 'blocked',
            schema_version: SCHEMA_VERSION,
            approved_plan_id: Value.fetch(value, :approved_plan_id),
            findings: [
              {
                code: error.code,
                severity: 'error',
                message: error.message,
                path: error.path
              }.compact
            ]
          }
        end
      end

      class Store
        def write(path, value)
          payload = if value.is_a?(Document)
                      value.to_h
                    else
                      Loader.new.load(value).to_h
                    end
          path = File.expand_path(path)
          if File.exist?(path)
            existing = JSON.parse(File.read(path), symbolize_names: true)
            return path if existing == payload

            raise OutputConflict, path
          end

          FileUtils.mkdir_p(File.dirname(path))
          Tempfile.create(['.approved-plan-', '.tmp'], File.dirname(path)) do |file|
            file.write(JSON.pretty_generate(payload))
            file.write("\n")
            file.flush
            file.fsync
            file.close
            File.rename(file.path, path)
          end
          path
        end
      end
    end
  end
end
