# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'tempfile'

module SloRulesEngine
  module ReleaseBundle
    class ApplyError < StandardError
      attr_reader :code, :findings, :target_uid, :completed_targets, :path

      def initialize(code, message, findings: [], target_uid: nil, completed_targets: [], path: nil)
        @code = code
        @findings = findings
        @target_uid = target_uid
        @completed_targets = completed_targets
        @path = path
        super(message)
      end
    end

    class OutputConflict < ApplyError
      def initialize(path)
        super(
          'release_bundle_output_conflict',
          "release bundle output already exists with different content at #{path}",
          path: path
        )
      end
    end

    class Applier
      FILE_AUTOMATION_MODES = %w[manifest_bundle external_generator].freeze
      SUCCESS_STATUSES = %w[succeeded noop].freeze

      def initialize(executor:, status_evaluator: StatusEvaluator.new)
        @executor = executor
        @status_evaluator = status_evaluator
      end

      def apply(bundle, approved_plans:)
        validate_predecessor!(bundle)
        targets = Array(ProviderState::Value.fetch(bundle, :targets))
        validate_target_modes!(targets)
        documents = normalize_approved_plans(approved_plans)
        ordered = validate_coverage!(bundle, targets, documents)

        completed = []
        ordered.each do |target, document|
          applied_plan = execute_target(document, completed)
          execution = execution_record(target, applied_plan)
          status = ProviderState::Value.fetch(ProviderState::Value.fetch(execution, :result), :status).to_s
          unless SUCCESS_STATUSES.include?(status)
            raise ApplyError.new(
              'bundle_target_execution_incomplete',
              "bundle apply stopped after target #{ProviderState::Value.fetch(target, :uid).inspect} returned #{status.inspect}",
              target_uid: ProviderState::Value.fetch(target, :uid),
              completed_targets: completed,
              findings: [
                {
                  code: 'bundle_target_execution_incomplete',
                  target_uid: ProviderState::Value.fetch(target, :uid),
                  result_status: status,
                  operation_journal: ProviderState::Value.fetch(execution, :operation_journal)
                }
              ]
            )
          end
          completed << execution
        end

        build_successor(bundle, completed)
      end

      private

      def validate_predecessor!(bundle)
        status = @status_evaluator.evaluate(bundle)
        return if status[:valid] && status[:effective_lifecycle] == 'apply_ready'

        lifecycle = status[:effective_lifecycle]
        code = lifecycle == 'stale' ? 'stale_bundle' : 'invalid_bundle_lifecycle'
        raise ApplyError.new(
          code,
          "bundle apply requires a valid apply_ready predecessor; effective lifecycle is #{lifecycle.inspect}",
          findings: status[:findings]
        )
      end

      def validate_target_modes!(targets)
        unsupported = targets.reject do |target|
          FILE_AUTOMATION_MODES.include?(ProviderState::Value.fetch(target, :automation_mode).to_s)
        end
        return if unsupported.empty?

        raise ApplyError.new(
          'unsupported_bundle_apply_target',
          'bundle apply supports only file-backed manifest_bundle and external_generator targets',
          findings: unsupported.map do |target|
            {
              code: 'unsupported_bundle_apply_target',
              target_uid: ProviderState::Value.fetch(target, :uid),
              automation_mode: ProviderState::Value.fetch(target, :automation_mode),
              message: 'live API and mixed live/file bundle execution is not supported'
            }
          end
        )
      end

      def normalize_approved_plans(values)
        entries = values.is_a?(Hash) ? values.values : Array(values)
        entries.map do |value|
          value.is_a?(ProviderState::ApprovedPlan::Document) ? value : ProviderState::ApprovedPlan::Loader.new.load(value)
        end
      end

      def validate_coverage!(bundle, targets, documents)
        target_uids = targets.map { |target| ProviderState::Value.fetch(target, :uid).to_s }
        grouped = documents.group_by { |document| ProviderState::Value.fetch(document.target, :uid).to_s }
        findings = []
        (target_uids - grouped.keys).sort.each do |target_uid|
          findings << {
            code: 'missing_approved_plan',
            target_uid: target_uid,
            message: 'one approved provider plan is required for this bundle target'
          }
        end
        (grouped.keys - target_uids).sort.each do |target_uid|
          findings << {
            code: 'unknown_approved_plan_target',
            target_uid: target_uid,
            message: 'approved provider plan target is not present in the source bundle'
          }
        end
        grouped.sort.each do |target_uid, matches|
          next unless matches.length > 1

          findings << {
            code: 'duplicate_approved_plan_target',
            target_uid: target_uid,
            count: matches.length,
            message: 'exactly one approved provider plan is allowed for each bundle target'
          }
        end
        unless findings.empty?
          raise ApplyError.new(
            'incomplete_approved_plan_coverage',
            'approved provider plans must cover every bundle target exactly once',
            findings: findings
          )
        end

        artifacts = Array(ProviderState::Value.fetch(bundle, :artifacts)).to_h do |artifact|
          [ProviderState::Value.fetch(artifact, :uid).to_s, artifact]
        end
        targets.sort_by { |target| ProviderState::Value.fetch(target, :uid).to_s }.map do |target|
          document = grouped.fetch(ProviderState::Value.fetch(target, :uid).to_s).fetch(0)
          validate_document_against_bundle!(bundle, target, document, artifacts)
          [target, document]
        end
      end

      def validate_document_against_bundle!(bundle, target, document, artifacts)
        target_uid = ProviderState::Value.fetch(target, :uid).to_s
        findings = []
        compare(
          findings,
          'approved_plan_source_bundle_mismatch',
          'source_bundle.bundle_id',
          ProviderState::Value.fetch(bundle, :bundle_id),
          ProviderState::Value.fetch(document.source_bundle, :bundle_id)
        )
        %i[uid scope service provider automation_mode].each do |key|
          compare(
            findings,
            'approved_plan_target_mismatch',
            "target.#{key}",
            ProviderState::Value.fetch(target, key),
            ProviderState::Value.fetch(document.target, key)
          )
        end
        compare(
          findings,
          'approved_plan_bundle_review_mismatch',
          'evidence.bundle_review_fingerprint',
          Fingerprint.content(ProviderState::Value.fetch(bundle, :review)),
          ProviderState::Value.fetch(document.evidence, :bundle_review_fingerprint)
        )

        scope = Array(ProviderState::Value.fetch(ProviderState::Value.fetch(bundle, :review), :scopes)).find do |entry|
          ProviderState::Value.fetch(entry, :label).to_s == ProviderState::Value.fetch(target, :scope).to_s
        end
        expected_uids = {
          change_plan: ProviderState::Value.fetch(target, :change_plan_artifact_uid),
          provider_manifest: ProviderState::Value.fetch(target, :manifest_artifact_uid),
          manifest_review_report: ProviderState::Value.fetch(target, :review_report_artifact_uid),
          reviewed_handoff: ProviderState::Value.fetch(scope, :handoff_artifact_uid)
        }
        expected_uids.each do |kind, artifact_uid|
          reference = ProviderState::Value.fetch(document.evidence, kind)
          compare(
            findings,
            'approved_plan_evidence_mismatch',
            "evidence.#{kind}.artifact_uid",
            artifact_uid,
            ProviderState::Value.fetch(reference, :artifact_uid)
          )
          artifact = artifacts[artifact_uid.to_s]
          compare(
            findings,
            'approved_plan_evidence_mismatch',
            "evidence.#{kind}.fingerprint",
            ProviderState::Value.fetch(artifact, :fingerprint),
            ProviderState::Value.fetch(reference, :fingerprint)
          )
        end

        bundled_plan = ProviderState::PlanLoader.new.load(
          ProviderState::Value.fetch(artifacts.fetch(expected_uids.fetch(:change_plan).to_s), :content)
        )
        compare(
          findings,
          'approved_plan_provider_plan_mismatch',
          'provider_plan.fingerprint',
          bundled_plan.fingerprint,
          document.provider_plan.fingerprint
        )
        return if findings.empty?

        raise ApplyError.new(
          'approved_plan_bundle_mismatch',
          "approved provider plan does not match bundle target #{target_uid.inspect}",
          target_uid: target_uid,
          findings: findings
        )
      rescue KeyError, ProviderState::ContractError => error
        raise ApplyError.new(
          'approved_plan_bundle_mismatch',
          "bundle target #{target_uid.inspect} cannot be reconciled with its approved provider plan: #{error.message}",
          target_uid: target_uid
        )
      end

      def compare(findings, code, path, expected, actual)
        return if expected == actual

        findings << {
          code: code,
          path: path,
          expected: ProviderState::Value.copy(expected),
          actual: ProviderState::Value.copy(actual)
        }
      end

      def execute_target(document, completed)
        @executor.execute(document)
      rescue ProviderState::ApprovedPlan::Error => error
        raise ApplyError.new(
          error.code,
          "bundle target #{ProviderState::Value.fetch(document.target, :uid).inspect} was not executed: #{error.message}",
          target_uid: ProviderState::Value.fetch(document.target, :uid),
          completed_targets: completed,
          findings: error.findings,
          path: error.path
        )
      rescue ProviderState::JournalConflict => error
        raise ApplyError.new(
          'operation_journal_conflict',
          error.message,
          target_uid: ProviderState::Value.fetch(document.target, :uid),
          completed_targets: completed,
          path: error.path
        )
      end

      def execution_record(target, applied_plan)
        execution = applied_plan.execution
        unless execution.is_a?(Hash) &&
               ProviderState::Value.fetch(execution, :operation_journal).is_a?(Hash) &&
               ProviderState::Value.fetch(execution, :result).is_a?(Hash)
          raise ApplyError.new(
            'invalid_bundle_target_execution',
            "target #{ProviderState::Value.fetch(target, :uid).inspect} returned incomplete execution evidence",
            target_uid: ProviderState::Value.fetch(target, :uid)
          )
        end

        {
          schema_version: EXECUTION_SCHEMA_VERSION,
          kind: 'BundleTargetExecution',
          target_uid: ProviderState::Value.fetch(target, :uid),
          service: ProviderState::Value.fetch(target, :service),
          provider: ProviderState::Value.fetch(target, :provider),
          approved_plan: ProviderState::Value.copy(ProviderState::Value.fetch(execution, :approved_plan)),
          operation_journal: ProviderState::Value.copy(ProviderState::Value.fetch(execution, :operation_journal)),
          result: ProviderState::Value.copy(ProviderState::Value.fetch(execution, :result))
        }
      end

      def build_successor(bundle, executions)
        applied = JSON.parse(JSON.generate(bundle), symbolize_names: true)
        artifacts = Array(ProviderState::Value.fetch(applied, :artifacts))
        targets = Array(ProviderState::Value.fetch(applied, :targets))
        executions.each do |execution|
          target_uid = ProviderState::Value.fetch(execution, :target_uid).to_s
          target = targets.find { |entry| ProviderState::Value.fetch(entry, :uid).to_s == target_uid }
          artifact_uid = "execution:#{target_uid}"
          credential_paths = CredentialScanner.paths(execution, "artifacts.#{artifact_uid}.content")
          raise CredentialError, credential_paths unless credential_paths.empty?

          artifacts.reject! { |artifact| ProviderState::Value.fetch(artifact, :uid).to_s == artifact_uid }
          artifacts << {
            uid: artifact_uid,
            kind: 'execution_result',
            scope: ProviderState::Value.fetch(target, :scope),
            provider: ProviderState::Value.fetch(target, :provider),
            content_type: 'application/json',
            fingerprint: Fingerprint.content(execution),
            source: {
              type: 'generated',
              predecessor_bundle_id: ProviderState::Value.fetch(bundle, :bundle_id),
              target_uid: target_uid
            },
            content: execution
          }
          target[:execution_artifact_uid] = artifact_uid
        end
        artifacts.sort_by! { |artifact| ProviderState::Value.fetch(artifact, :uid).to_s }
        targets.sort_by! { |target| ProviderState::Value.fetch(target, :uid).to_s }
        applied[:transition] = {
          action: 'apply',
          predecessor_bundle_id: ProviderState::Value.fetch(bundle, :bundle_id),
          predecessor_lifecycle: ProviderState::Value.fetch(bundle, :lifecycle)
        }
        applied[:lifecycle] = 'applied'
        applied[:summary] = SummaryBuilder.new.build(
          review: ProviderState::Value.fetch(applied, :review),
          targets: targets,
          artifacts: artifacts,
          findings: Array(ProviderState::Value.fetch(applied, :findings))
        )
        applied[:bundle_id] = Fingerprint.bundle_id(applied)
        SchemaValidator.validate!(applied)
        status = @status_evaluator.evaluate(applied)
        return applied if status[:valid] && status[:effective_lifecycle] == 'applied'

        raise ApplyError.new(
          'invalid_applied_bundle',
          'generated applied bundle failed status validation',
          findings: status[:findings]
        )
      end
    end

    class Store
      def preflight(path, predecessor_bundle_id:, approved_plan_ids:)
        path = File.expand_path(path)
        return nil unless File.exist?(path)

        existing = JSON.parse(File.read(path), symbolize_names: true)
        status = StatusEvaluator.new.evaluate(existing)
        transition = ProviderState::Value.fetch(existing, :transition)
        execution_plan_ids = Array(ProviderState::Value.fetch(existing, :artifacts)).filter_map do |artifact|
          next unless ProviderState::Value.fetch(artifact, :kind) == 'execution_result'

          ProviderState::Value.fetch(
            ProviderState::Value.fetch(
              ProviderState::Value.fetch(artifact, :content),
              :approved_plan
            ),
            :approved_plan_id
          )
        end.sort
        compatible = status[:valid] &&
                     status[:effective_lifecycle] == 'applied' &&
                     ProviderState::Value.fetch(transition, :action) == 'apply' &&
                     ProviderState::Value.fetch(transition, :predecessor_bundle_id) == predecessor_bundle_id &&
                     execution_plan_ids == Array(approved_plan_ids).map(&:to_s).sort
        raise OutputConflict, path unless compatible

        existing
      rescue JSON::ParserError
        raise OutputConflict, path
      end

      def write(path, bundle)
        SchemaValidator.validate!(bundle)
        path = File.expand_path(path)
        payload = JSON.parse(JSON.generate(bundle))
        FileUtils.mkdir_p(File.dirname(path))
        File.open("#{path}.lock", File::RDWR | File::CREAT, 0o600) do |lock|
          lock.flock(File::LOCK_EX)
          if File.exist?(path)
            existing = JSON.parse(File.read(path))
            return path if existing == payload

            raise OutputConflict, path
          end

          Tempfile.create(['.release-bundle-', '.tmp'], File.dirname(path)) do |file|
            file.write(JSON.pretty_generate(payload))
            file.write("\n")
            file.flush
            file.fsync
            file.close
            File.rename(file.path, path)
          end
        ensure
          lock.flock(File::LOCK_UN)
        end
        path
      end
    end
  end
end
