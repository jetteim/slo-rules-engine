# frozen_string_literal: true

require 'json'
require 'time'

module SloRulesEngine
  module ReleaseBundle
    class VerifyError < StandardError
      attr_reader :code, :findings, :target_uid, :path

      def initialize(code, message, findings: [], target_uid: nil, path: nil)
        @code = code
        @findings = findings
        @target_uid = target_uid
        @path = path
        super(message)
      end
    end

    class Verifier
      FILE_AUTOMATION_MODES = %w[manifest_bundle external_generator].freeze
      RESULT_STATUSES = %w[succeeded noop].freeze
      ENGINE_REQUIREMENTS = %w[refresh_managed_file_state compare_desired_state].freeze

      def initialize(
        status_evaluator: StatusEvaluator.new,
        verifier: ProviderState::ManagedFileVerifier.new,
        journal_reader: nil,
        clock: -> { Time.now.utc }
      )
        @status_evaluator = status_evaluator
        @verifier = verifier
        @journal_reader = journal_reader || method(:read_journal)
        @clock = clock
      end

      def verify(bundle, checked_at: nil)
        validate_predecessor!(bundle)
        targets = Array(ProviderState::Value.fetch(bundle, :targets))
        validate_target_modes!(targets)
        contexts = preflight_targets!(bundle, targets)
        timestamp = normalize_timestamp(checked_at || @clock.call)
        verifications = contexts.map { |context| verify_target!(context, timestamp) }

        build_successor(bundle, verifications)
      end

      private

      def validate_predecessor!(bundle)
        status = @status_evaluator.evaluate(bundle)
        return if status[:valid] && status[:effective_lifecycle] == 'applied'

        lifecycle = status[:effective_lifecycle]
        code = lifecycle == 'stale' ? 'stale_bundle' : 'invalid_bundle_lifecycle'
        raise VerifyError.new(
          code,
          "bundle verify requires a valid applied predecessor; effective lifecycle is #{lifecycle.inspect}",
          findings: status[:findings]
        )
      end

      def validate_target_modes!(targets)
        unsupported = targets.reject do |target|
          FILE_AUTOMATION_MODES.include?(
            ProviderState::Value.fetch(target, :automation_mode).to_s
          )
        end
        return if unsupported.empty?

        raise VerifyError.new(
          'unsupported_bundle_verify_target',
          'bundle verify supports only file-backed manifest_bundle and external_generator targets',
          findings: unsupported.map do |target|
            {
              code: 'unsupported_bundle_verify_target',
              target_uid: ProviderState::Value.fetch(target, :uid),
              automation_mode: ProviderState::Value.fetch(target, :automation_mode),
              message: 'live API and mixed live/file bundle verification is not supported'
            }
          end
        )
      end

      def preflight_targets!(bundle, targets)
        artifacts = Array(ProviderState::Value.fetch(bundle, :artifacts)).to_h do |artifact|
          [ProviderState::Value.fetch(artifact, :uid).to_s, artifact]
        end
        findings = []
        contexts = targets.sort_by { |target| ProviderState::Value.fetch(target, :uid).to_s }.filter_map do |target|
          preflight_target(bundle, target, artifacts, findings)
        end
        return contexts if findings.empty?

        raise VerifyError.new(
          'invalid_bundle_verification_inputs',
          'bundle verification inputs failed integrity preflight',
          findings: findings,
          target_uid: ProviderState::Value.fetch(findings.first, :target_uid),
          path: ProviderState::Value.fetch(findings.first, :path)
        )
      end

      def preflight_target(bundle, target, artifacts, findings)
        target_uid = ProviderState::Value.fetch(target, :uid).to_s
        execution_artifact = artifacts[
          ProviderState::Value.fetch(target, :execution_artifact_uid).to_s
        ]
        plan_artifact = artifacts[
          ProviderState::Value.fetch(target, :change_plan_artifact_uid).to_s
        ]
        execution = ProviderState::Value.fetch(execution_artifact, :content)
        plan = ProviderState::PlanLoader.new.load(
          ProviderState::Value.fetch(plan_artifact, :content)
        )
        journal_reference = ProviderState::Value.fetch(execution, :operation_journal)
        journal_path = ProviderState::Value.fetch(journal_reference, :path)
        journal = @journal_reader.call(journal_path)
        evaluation = ProviderState::JournalEvaluator.new.evaluate(journal)
        unless evaluation.fetch(:valid)
          findings.concat(evaluation.fetch(:findings).map do |finding|
            normalize_finding(finding, target_uid: target_uid, journal_path: journal_path)
          end)
          return
        end

        validate_execution_lineage(
          bundle,
          target,
          execution_artifact,
          execution,
          plan,
          journal,
          journal_reference,
          findings
        )
        return if findings.any? { |finding| finding[:target_uid] == target_uid }

        {
          target: target,
          execution: execution,
          plan: plan,
          journal: journal
        }
      rescue KeyError, JSON::ParserError, SystemCallError, TypeError, ProviderState::ContractError => error
        findings << {
          code: 'invalid_bundle_verification_input',
          severity: 'error',
          target_uid: target_uid,
          path: error.respond_to?(:path) ? error.path : journal_path,
          message: error.message
        }.compact
        nil
      end

      def validate_execution_lineage(
        bundle,
        target,
        execution_artifact,
        execution,
        plan,
        journal,
        journal_reference,
        findings
      )
        target_uid = ProviderState::Value.fetch(target, :uid).to_s
        transition = ProviderState::Value.fetch(bundle, :transition)
        approved_plan = ProviderState::Value.fetch(execution, :approved_plan)
        runtime = ProviderState::Value.fetch(execution, :runtime)
        result = ProviderState::Value.fetch(execution, :result)
        journal_plan = ProviderState::Value.fetch(journal, :plan)
        live_plan = ProviderState::Plan.new(
          provider: plan.provider,
          service: plan.service,
          mode: 'live',
          desired_state: plan.desired_state,
          observed_state: plan.observed_state,
          changes: plan.changes,
          findings: plan.findings,
          summary: plan.summary
        )
        comparisons = {
          'execution source predecessor' => [
            ProviderState::Value.fetch(transition, :predecessor_bundle_id),
            ProviderState::Value.fetch(
              ProviderState::Value.fetch(execution_artifact, :source),
              :predecessor_bundle_id
            )
          ],
          'approved plan source bundle' => [
            ProviderState::Value.fetch(transition, :predecessor_bundle_id),
            ProviderState::Value.fetch(approved_plan, :source_bundle_id)
          ],
          'approved provider plan fingerprint' => [
            plan.fingerprint,
            ProviderState::Value.fetch(approved_plan, :provider_plan_fingerprint)
          ],
          'journal id' => [
            ProviderState::Value.fetch(journal_reference, :journal_id),
            ProviderState::Value.fetch(journal, :journal_id)
          ],
          'journal status' => [
            ProviderState::Value.fetch(journal_reference, :status),
            ProviderState::Value.fetch(journal, :status)
          ],
          'journal fingerprint' => [
            ProviderState::Value.fetch(journal_reference, :fingerprint),
            ProviderState::Fingerprint.content(journal)
          ],
          'journal approved plan' => [
            approved_plan,
            ProviderState::Value.fetch(journal_plan, :approved_plan)
          ],
          'journal live plan fingerprint' => [
            live_plan.fingerprint,
            ProviderState::Value.fetch(journal_plan, :fingerprint)
          ],
          'journal provider' => [
            ProviderState::Value.fetch(target, :provider),
            ProviderState::Value.fetch(journal, :provider)
          ],
          'journal service' => [
            ProviderState::Value.fetch(target, :service),
            ProviderState::Value.fetch(journal, :service)
          ],
          'result provider' => [
            ProviderState::Value.fetch(target, :provider),
            ProviderState::Value.fetch(result, :provider)
          ],
          'result service' => [
            ProviderState::Value.fetch(target, :service),
            ProviderState::Value.fetch(result, :service)
          ],
          'result plan fingerprint' => [
            ProviderState::Value.fetch(journal_plan, :fingerprint),
            ProviderState::Value.fetch(result, :plan_fingerprint)
          ],
          'result desired-state fingerprint' => [
            ProviderState::Value.fetch(journal_plan, :desired_state_fingerprint),
            ProviderState::Value.fetch(result, :desired_state_fingerprint)
          ],
          'result observed-state fingerprint' => [
            ProviderState::Value.fetch(journal_plan, :observed_state_fingerprint),
            ProviderState::Value.fetch(result, :observed_state_fingerprint)
          ]
        }
        comparisons.each do |label, (expected, actual)|
          compare(findings, target_uid, label, expected, actual)
        end
        expected_result = ProviderState::ResultBuilder.new.build(
          plan: live_plan,
          journal: journal
        ).to_h
        compare(
          findings,
          target_uid,
          'terminal provider result',
          expected_result,
          ProviderState::Value.copy(result)
        )
        compare(
          findings,
          target_uid,
          'execution result schema',
          ProviderState::SCHEMA_VERSION,
          ProviderState::Value.fetch(result, :schema_version)
        )
        compare(
          findings,
          target_uid,
          'execution result kind',
          'ProviderStateResult',
          ProviderState::Value.fetch(result, :kind)
        )
        unless RESULT_STATUSES.include?(ProviderState::Value.fetch(result, :status).to_s)
          findings << mismatch_finding(
            target_uid,
            'execution result status',
            RESULT_STATUSES,
            ProviderState::Value.fetch(result, :status)
          )
        end
        unless ProviderState::Value.fetch(journal, :status) == 'succeeded'
          findings << mismatch_finding(
            target_uid,
            'operation journal status',
            'succeeded',
            ProviderState::Value.fetch(journal, :status)
          )
        end

        validate_runtime_paths(target, runtime, plan, journal, findings)
        validate_journal_entries(target_uid, plan, journal, findings)
      end

      def validate_runtime_paths(target, runtime, plan, journal, findings)
        target_uid = ProviderState::Value.fetch(target, :uid).to_s
        output_dir = ProviderState::Value.fetch(runtime, :output_dir)
        if output_dir.to_s.empty?
          findings << mismatch_finding(target_uid, 'runtime output directory', 'present', output_dir)
          return
        end
        root = File.join(
          File.expand_path(output_dir),
          ProviderState::Value.fetch(target, :service).to_s,
          ProviderState::Value.fetch(target, :provider).to_s
        )
        prefix = "#{root}#{File::SEPARATOR}"
        paths = plan.changes.filter_map do |change|
          ProviderState::Value.fetch(change.desired, :path)
        end
        paths.concat(Array(ProviderState::Value.fetch(journal, :entries)).filter_map do |entry|
          ProviderState::Value.fetch(ProviderState::Value.fetch(entry, :desired), :path)
        end)
        paths.each do |path|
          next if File.expand_path(path).start_with?(prefix)

          findings << {
            code: 'bundle_verification_runtime_mismatch',
            severity: 'error',
            target_uid: target_uid,
            path: path,
            message: 'managed path escapes the approved target runtime'
          }
        end
      end

      def validate_journal_entries(target_uid, plan, journal, findings)
        entries = Array(ProviderState::Value.fetch(journal, :entries))
        unless entries.length == plan.changes.length
          findings << mismatch_finding(
            target_uid,
            'journal operation count',
            plan.changes.length,
            entries.length
          )
          return
        end

        plan.changes.each_with_index do |change, index|
          entry = entries.fetch(index)
          compare(findings, target_uid, "journal entry #{index} position", index,
                  ProviderState::Value.fetch(entry, :position))
          {
            action: change.action,
            target: change.target,
            name: change.name,
            source: change.source,
            desired: change.desired,
            observed: change.observed,
            changed_paths: change.changed_paths,
            provider_resource_id: change.provider_resource_id,
            match_identity: change.match_identity,
            risk: change.risk
          }.each do |key, expected|
            compare(
              findings,
              target_uid,
              "journal entry #{index} #{key}",
              ProviderState::Value.copy(expected),
              ProviderState::Value.copy(ProviderState::Value.fetch(entry, key))
            )
          end
        end
      end

      def verify_target!(context, checked_at)
        target = context.fetch(:target)
        target_uid = ProviderState::Value.fetch(target, :uid).to_s
        resources = Array(ProviderState::Value.fetch(context.fetch(:journal), :entries)).map do |entry|
          if external_entry?(entry)
            pending_external_resource(entry)
          else
            verify_engine_resource(entry, checked_at)
          end
        end
        failed = resources.reject do |resource|
          external_resource?(resource) || ProviderState::Value.fetch(resource, :status) == 'succeeded'
        end
        unless failed.empty?
          raise VerifyError.new(
            'bundle_target_verification_failed',
            "managed files for bundle target #{target_uid.inspect} do not converge",
            target_uid: target_uid,
            findings: failed.flat_map do |resource|
              Array(ProviderState::Value.fetch(resource, :findings)).map do |finding|
                normalize_finding(
                  finding,
                  target_uid: target_uid,
                  entry_id: ProviderState::Value.fetch(resource, :entry_id)
                )
              end
            end
          )
        end

        verification = verification_rollup(resources, checked_at)
        {
          schema_version: VERIFICATION_SCHEMA_VERSION,
          kind: 'BundleTargetVerification',
          target_uid: target_uid,
          service: ProviderState::Value.fetch(target, :service),
          provider: ProviderState::Value.fetch(target, :provider),
          checked_at: checked_at,
          status: 'succeeded',
          runtime: ProviderState::Value.copy(
            ProviderState::Value.fetch(context.fetch(:execution), :runtime)
          ),
          approved_plan: ProviderState::Value.copy(
            ProviderState::Value.fetch(context.fetch(:execution), :approved_plan)
          ),
          operation_journal: ProviderState::Value.copy(
            ProviderState::Value.fetch(context.fetch(:execution), :operation_journal)
          ),
          provider_plan: {
            fingerprint: context.fetch(:plan).fingerprint,
            desired_state_fingerprint: context.fetch(:plan).desired_state.fingerprint,
            observed_state_fingerprint: context.fetch(:plan).observed_state.fingerprint
          },
          verification: verification,
          findings: []
        }
      end

      def verify_engine_resource(entry, checked_at)
        evidence = @verifier.verify(entry, checked_at: checked_at)
        {
          entry_id: ProviderState::Value.fetch(entry, :entry_id),
          target: ProviderState::Value.fetch(entry, :target),
          name: ProviderState::Value.fetch(entry, :name),
          source: ProviderState::Value.fetch(entry, :source),
          ownership: 'engine',
          requirements: ENGINE_REQUIREMENTS
        }.merge(ProviderState::Value.copy(evidence))
      end

      def pending_external_resource(entry)
        verification = ProviderState::Value.fetch(entry, :verification)
        {
          entry_id: ProviderState::Value.fetch(entry, :entry_id),
          target: ProviderState::Value.fetch(entry, :target),
          name: ProviderState::Value.fetch(entry, :name),
          source: ProviderState::Value.fetch(entry, :source),
          ownership: 'external',
          status: 'pending',
          requirements: ProviderState::Value.copy(
            Array(ProviderState::Value.fetch(verification, :requirements))
          ),
          findings: []
        }
      end

      def verification_rollup(resources, checked_at)
        engine = resources.reject { |resource| external_resource?(resource) }
        external = resources.select { |resource| external_resource?(resource) }
        statuses = resources.map { |resource| ProviderState::Value.fetch(resource, :status).to_s }
        external_status = external.empty? ? 'not_required' : resource_status(external)
        {
          status: external_status == 'pending' ? 'pending' : resource_status(resources),
          engine_owned_status: resource_status(engine),
          external_status: external_status,
          checked_at: checked_at,
          requirements: resources.flat_map do |resource|
            Array(ProviderState::Value.fetch(resource, :requirements))
          end.uniq,
          summary: {
            required_resources: resources.length,
            pending_resources: statuses.count('pending'),
            succeeded_resources: statuses.count('succeeded'),
            failed_resources: statuses.count('failed'),
            engine_owned_resources: engine.length,
            external_resources: external.length
          },
          resources: resources
        }
      end

      def resource_status(resources)
        statuses = resources.map { |resource| ProviderState::Value.fetch(resource, :status).to_s }
        return 'not_required' if resources.empty?
        return 'failed' if statuses.include?('failed')
        return 'pending' if statuses.include?('pending')

        'succeeded'
      end

      def external_entry?(entry)
        ProviderState::Value.fetch(entry, :action) == 'handoff' ||
          ProviderState::Value.fetch(entry, :target) == 'external_generator'
      end

      def external_resource?(resource)
        ProviderState::Value.fetch(resource, :ownership) == 'external'
      end

      def build_successor(bundle, verifications)
        verified = JSON.parse(JSON.generate(bundle), symbolize_names: true)
        artifacts = Array(ProviderState::Value.fetch(verified, :artifacts))
        targets = Array(ProviderState::Value.fetch(verified, :targets))
        verifications.each do |verification|
          target_uid = ProviderState::Value.fetch(verification, :target_uid).to_s
          target = targets.find do |entry|
            ProviderState::Value.fetch(entry, :uid).to_s == target_uid
          end
          artifact_uid = "verification:#{target_uid}"
          credential_paths = CredentialScanner.paths(
            verification,
            "artifacts.#{artifact_uid}.content"
          )
          raise CredentialError, credential_paths unless credential_paths.empty?

          artifacts.reject! do |artifact|
            ProviderState::Value.fetch(artifact, :uid).to_s == artifact_uid
          end
          artifacts << {
            uid: artifact_uid,
            kind: 'target_verification',
            scope: ProviderState::Value.fetch(target, :scope),
            provider: ProviderState::Value.fetch(target, :provider),
            content_type: 'application/json',
            fingerprint: Fingerprint.content(verification),
            source: {
              type: 'generated',
              predecessor_bundle_id: ProviderState::Value.fetch(bundle, :bundle_id),
              target_uid: target_uid
            },
            content: verification
          }
          target[:verification_artifact_uid] = artifact_uid
        end
        artifacts.sort_by! { |artifact| ProviderState::Value.fetch(artifact, :uid).to_s }
        targets.sort_by! { |target| ProviderState::Value.fetch(target, :uid).to_s }
        verified[:transition] = {
          action: 'verify',
          predecessor_bundle_id: ProviderState::Value.fetch(bundle, :bundle_id),
          predecessor_lifecycle: ProviderState::Value.fetch(bundle, :lifecycle)
        }
        verified[:lifecycle] = 'verified'
        verified[:summary] = SummaryBuilder.new.build(
          review: ProviderState::Value.fetch(verified, :review),
          targets: targets,
          artifacts: artifacts,
          findings: Array(ProviderState::Value.fetch(verified, :findings))
        )
        verified[:bundle_id] = Fingerprint.bundle_id(verified)
        SchemaValidator.validate!(verified)
        status = @status_evaluator.evaluate(verified)
        return verified if status[:valid] && status[:effective_lifecycle] == 'verified'

        raise VerifyError.new(
          'invalid_verified_bundle',
          'generated verified bundle failed status validation',
          findings: status[:findings]
        )
      end

      def compare(findings, target_uid, path, expected, actual)
        return if expected == actual

        findings << mismatch_finding(target_uid, path, expected, actual)
      end

      def mismatch_finding(target_uid, path, expected, actual)
        {
          code: 'bundle_verification_evidence_mismatch',
          severity: 'error',
          target_uid: target_uid,
          path: path,
          message: 'packaged execution evidence does not match its verified source',
          expected: ProviderState::Value.copy(expected),
          actual: ProviderState::Value.copy(actual)
        }
      end

      def normalize_finding(finding, **context)
        normalized = finding.to_h.each_with_object({}) do |(key, value), result|
          result[key.to_sym] = ProviderState::Value.copy(value)
        end
        context.merge(normalized)
      end

      def read_journal(path)
        JSON.parse(File.read(path), symbolize_names: true)
      end

      def normalize_timestamp(value)
        time = value.respond_to?(:utc) ? value.utc : Time.iso8601(value.to_s).utc
        time.iso8601(6)
      rescue ArgumentError
        raise VerifyError.new(
          'invalid_bundle_verification_timestamp',
          'bundle verification timestamp must be ISO 8601'
        )
      end
    end
  end
end
