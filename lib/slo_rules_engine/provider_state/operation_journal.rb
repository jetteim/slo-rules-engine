# frozen_string_literal: true

require 'time'

module SloRulesEngine
  module ProviderState
    JOURNAL_SCHEMA_VERSION = 'slo-rules-engine/provider-operation-journal/v1'

    class OperationJournal
      ENTRY_STATUSES = %w[pending running succeeded failed skipped].freeze
      STATUSES = %w[pending running succeeded partial failed blocked].freeze
      RESUME_CLASSIFICATIONS = %w[
        no_execution_required
        retry_after_state_recheck
        manual_intervention_required
      ].freeze
      VERIFICATION_STATUSES = %w[pending succeeded failed not_required].freeze
      IDENTITY_ENTRY_KEYS = %i[
        entry_id
        position
        action
        target
        name
        source
        desired
        observed
        changed_paths
        provider_resource_id
        match_identity
        risk
        resume
      ].freeze

      attr_reader :journal_id, :provider, :service, :status, :plan, :entries, :findings

      def self.journal_id_for(provider:, service:, plan:, entries:)
        identity_entries = entries.map do |entry|
          identity = IDENTITY_ENTRY_KEYS.each_with_object({}) do |key, values|
            value = Value.fetch(entry, key)
            values[key] = value unless value.nil?
          end
          verification = Value.fetch(entry, :verification)
          identity[:verification] = {
            required: Value.fetch(verification, :required),
            requirements: Value.fetch(verification, :requirements)
          } if verification.is_a?(Hash)
          identity
        end
        "operation-journal-#{Fingerprint.content(
          provider: provider,
          service: service,
          plan: plan,
          entries: identity_entries
        )}"
      end

      def initialize(provider:, service:, plan:, entries:, findings:)
        Value.require_presence!('provider', provider)
        Value.require_presence!('service', service)
        raise ContractError.new('plan', 'must be a hash') unless plan.is_a?(Hash)
        raise ContractError.new('entries', 'must be an array') unless entries.is_a?(Array)
        Value.require_instances!('findings', findings, Finding)

        entries.each_with_index do |entry, index|
          raise ContractError.new("entries[#{index}]", 'must be a hash') unless entry.is_a?(Hash)

          Value.require_one_of!(
            "entries[#{index}].status",
            Value.fetch(entry, :status),
            ENTRY_STATUSES
          )
        end
        credential_paths = CredentialScanner.paths(
          {
            provider: provider,
            service: service,
            plan: plan,
            entries: entries,
            findings: findings.map(&:to_h)
          },
          'journal'
        )
        unless credential_paths.empty?
          raise ContractError.new(credential_paths.first, 'credential-like keys are forbidden')
        end

        @provider = provider.to_s.freeze
        @service = service.to_s.freeze
        @plan = Value.immutable(plan)
        @entries = Value.immutable(entries)
        @findings = Value.immutable(findings)
        @status = initial_status.freeze
        @journal_id = self.class.journal_id_for(
          provider: @provider,
          service: @service,
          plan: @plan,
          entries: @entries
        ).freeze
        freeze
      end

      def to_h
        {
          schema_version: JOURNAL_SCHEMA_VERSION,
          kind: 'ProviderOperationJournal',
          journal_id: journal_id,
          provider: provider,
          service: service,
          status: status,
          plan: Value.copy(plan),
          entries: Value.copy(entries),
          summary: summary,
          findings: findings.map(&:to_h)
        }
      end

      private

      def initial_status
        return 'pending' if entries.any? { |entry| Value.fetch(entry, :status) == 'pending' }

        'succeeded'
      end

      def summary
        counts = ENTRY_STATUSES.to_h { |entry_status| [entry_status, 0] }
        entries.each { |entry| counts[Value.fetch(entry, :status)] += 1 }
        {
          total_entries: entries.length,
          actionable_entries: entries.count { |entry| Value.fetch(entry, :action) != 'noop' },
          pending_entries: counts.fetch('pending'),
          running_entries: counts.fetch('running'),
          succeeded_entries: counts.fetch('succeeded'),
          failed_entries: counts.fetch('failed'),
          skipped_entries: counts.fetch('skipped'),
          resume_eligible_entries: entries.count { |entry| Value.fetch(Value.fetch(entry, :resume), :eligible) },
          resume_blocked_entries: entries.count do |entry|
            Value.fetch(entry, :action) != 'noop' && !Value.fetch(Value.fetch(entry, :resume), :eligible)
          end,
          verification_required_entries: entries.count do |entry|
            Value.fetch(Value.fetch(entry, :verification), :required)
          end,
          verification_pending_entries: verification_count('pending'),
          verification_succeeded_entries: verification_count('succeeded'),
          verification_failed_entries: verification_count('failed'),
          verification_not_required_entries: verification_count('not_required')
        }
      end

      def verification_count(status)
        entries.count do |entry|
          Value.fetch(Value.fetch(entry, :verification), :status) == status
        end
      end
    end

    class JournalBuilder
      RESUMABLE_ACTIONS = %w[update write].freeze

      def initialize(accepted_modes: ['dry_run'])
        @accepted_modes = accepted_modes
      end

      def build(plan, approved_plan_reference: nil)
        raise ContractError.new('plan', 'must be a ProviderStatePlan') unless plan.is_a?(Plan)
        unless @accepted_modes.include?(plan.mode)
          raise ContractError.new('plan.mode', "must be one of #{@accepted_modes.inspect} for journal creation")
        end

        entries = plan.changes.each_with_index.map { |change, index| build_entry(plan, change, index) }
        OperationJournal.new(
          provider: plan.provider,
          service: plan.service,
          plan: plan_reference(plan, approved_plan_reference),
          entries: entries,
          findings: journal_findings(plan, entries)
        )
      end

      private

      def build_entry(plan, change, index)
        resume_policy = resume_policy(change.action)
        verification = verification_policy(plan.provider, change.action)
        Value.compact(
          entry_id: operation_id(plan, change, index),
          position: index,
          action: change.action,
          target: change.target,
          name: change.name,
          source: change.source,
          status: change.action == 'noop' ? 'skipped' : 'pending',
          desired: Value.copy(change.desired),
          observed: Value.copy(change.observed),
          changed_paths: Value.copy(change.changed_paths),
          provider_resource_id: Value.copy(change.provider_resource_id),
          match_identity: Value.copy(change.match_identity),
          risk: Value.copy(change.risk),
          resume: resume_policy,
          verification: verification,
          attempts: []
        )
      end

      def plan_reference(plan, approved_plan_reference)
        reference = {
          schema_version: SCHEMA_VERSION,
          kind: 'ProviderStatePlanReference',
          fingerprint: plan.fingerprint,
          mode: plan.mode,
          desired_state_fingerprint: plan.desired_state.fingerprint,
          observed_state_fingerprint: plan.observed_state.fingerprint
        }
        reference[:approved_plan] = Value.copy(approved_plan_reference) if approved_plan_reference
        reference
      end

      def operation_id(plan, change, index)
        identity = {
          plan_fingerprint: plan.fingerprint,
          position: index,
          action: change.action,
          target: change.target,
          name: change.name,
          source: change.source
        }
        "operation-#{Fingerprint.content(identity)}"
      end

      def resume_policy(action)
        if action == 'noop'
          return {
            eligible: false,
            classification: 'no_execution_required',
            requires_state_recheck: false,
            reasons: ['operation records already-converged state']
          }
        end
        if RESUMABLE_ACTIONS.include?(action)
          return {
            eligible: true,
            classification: 'retry_after_state_recheck',
            requires_state_recheck: true,
            reasons: ['provider state may have changed after the recorded attempt']
          }
        end

        {
          eligible: false,
          classification: 'manual_intervention_required',
          requires_state_recheck: true,
          reasons: ['the operation may have completed before a failure was recorded']
        }
      end

      def verification_policy(provider, action)
        return { required: false, status: 'not_required', requirements: [] } if action == 'noop'
        if action == 'handoff'
          return {
            required: true,
            status: 'pending',
            requirements: ['confirm_external_generator_completion', 'refresh_downstream_provider_state']
          }
        end

        requirements = if %w[prometheus_stack sloth].include?(provider)
                         ['refresh_managed_file_state', 'compare_desired_state']
                       else
                         ['refresh_provider_state', 'compare_desired_state']
                       end
        {
          required: true,
          status: 'pending',
          requirements: requirements
        }
      end

      def journal_findings(plan, entries)
        entries.filter_map do |entry|
          next if Value.fetch(entry, :action) == 'noop'
          next if Value.fetch(Value.fetch(entry, :resume), :eligible)

          Finding.new(
            provider: plan.provider,
            code: 'non_resumable_operation',
            severity: 'warning',
            message: 'operation requires manual verification before retry after an uncertain failure',
            target: Value.fetch(entry, :target),
            source: Value.fetch(entry, :source),
            evidence: {
              entry_id: Value.fetch(entry, :entry_id),
              action: Value.fetch(entry, :action),
              classification: Value.fetch(Value.fetch(entry, :resume), :classification)
            }
          )
        end
      end
    end

    class JournalEvaluator
      def evaluate(journal)
        validate!(journal)
        entries = Value.fetch(journal, :entries)
        rollup = rollup(entries)
        failed = entries.select { |entry| Value.fetch(entry, :status) == 'failed' }
        blocked = failed.reject { |entry| Value.fetch(Value.fetch(entry, :resume), :eligible) }
        failed_verifications = entries.select do |entry|
          Value.fetch(Value.fetch(entry, :verification), :status) == 'failed'
        end
        effective_status = rollup.fetch(:status)
        findings = Array(Value.fetch(journal, :findings)).map { |finding| Value.copy(finding) }
        findings.concat(
          runtime_findings(
            Value.fetch(journal, :provider),
            effective_status,
            failed,
            blocked,
            failed_verifications
          )
        )

        {
          valid: true,
          schema_version: JOURNAL_SCHEMA_VERSION,
          journal_id: Value.fetch(journal, :journal_id),
          provider: Value.fetch(journal, :provider),
          service: Value.fetch(journal, :service),
          status: effective_status,
          plan: Value.copy(Value.fetch(journal, :plan)),
          summary: rollup.fetch(:summary),
          resume: {
            required: failed.any?,
            eligible: failed.any? && blocked.empty?,
            failed_entries: failed.map { |entry| Value.fetch(entry, :entry_id) },
            blocked_entries: blocked.map { |entry| Value.fetch(entry, :entry_id) },
            requires_state_recheck: failed.any? { |entry|
              Value.fetch(Value.fetch(entry, :resume), :requires_state_recheck)
            }
          },
          findings: findings
        }
      rescue ContractError => error
        {
          valid: false,
          schema_version: JOURNAL_SCHEMA_VERSION,
          journal_id: Value.fetch(journal, :journal_id),
          status: 'blocked',
          findings: [
            {
              code: 'invalid_operation_journal',
              severity: 'error',
              message: error.message,
              path: error.path
            }
          ]
        }
      end

      def rollup(entries)
        counts = OperationJournal::ENTRY_STATUSES.to_h { |entry_status| [entry_status, 0] }
        entries.each { |entry| counts[Value.fetch(entry, :status)] += 1 }
        verification_counts = OperationJournal::VERIFICATION_STATUSES.to_h do |verification_status|
          [verification_status, 0]
        end
        entries.each do |entry|
          verification = Value.fetch(entry, :verification)
          verification_counts[Value.fetch(verification, :status)] += 1
        end
        {
          status: effective_status(counts),
          summary: {
            total_entries: entries.length,
            pending_entries: counts.fetch('pending'),
            running_entries: counts.fetch('running'),
            succeeded_entries: counts.fetch('succeeded'),
            failed_entries: counts.fetch('failed'),
            skipped_entries: counts.fetch('skipped'),
            verification_pending_entries: verification_counts.fetch('pending'),
            verification_succeeded_entries: verification_counts.fetch('succeeded'),
            verification_failed_entries: verification_counts.fetch('failed'),
            verification_not_required_entries: verification_counts.fetch('not_required')
          }
        }
      end

      private

      def validate!(journal)
        raise ContractError.new('journal', 'must be a hash') unless journal.is_a?(Hash)
        require_equal!('schema_version', Value.fetch(journal, :schema_version), JOURNAL_SCHEMA_VERSION)
        require_equal!('kind', Value.fetch(journal, :kind), 'ProviderOperationJournal')
        provider = required('provider', journal)
        service = required('service', journal)
        plan = Value.fetch(journal, :plan)
        validate_plan_reference!(plan)

        entries = Value.fetch(journal, :entries)
        raise ContractError.new('entries', 'must be an array') unless entries.is_a?(Array)
        entry_ids = entries.each_with_index.map do |entry, index|
          raise ContractError.new("entries[#{index}]", 'must be a hash') unless entry.is_a?(Hash)

          Value.require_one_of!(
            "entries[#{index}].status",
            Value.fetch(entry, :status),
            OperationJournal::ENTRY_STATUSES
          )
          entry_id = required("entries[#{index}].entry_id", entry, :entry_id)
          unless entry_id.to_s.match?(/\Aoperation-[0-9a-f]{64}\z/)
            raise ContractError.new("entries[#{index}].entry_id", 'must be a deterministic operation identity')
          end
          Value.require_one_of!(
            "entries[#{index}].action",
            Value.fetch(entry, :action),
            Change::ACTIONS
          )
          %i[target name source].each do |key|
            required("entries[#{index}].#{key}", entry, key)
          end
          validate_resume_policy!(Value.fetch(entry, :resume), index)
          validate_verification_policy!(Value.fetch(entry, :verification), index)
          attempts = Value.fetch(entry, :attempts)
          raise ContractError.new("entries[#{index}].attempts", 'must be an array') unless attempts.is_a?(Array)
          validate_attempts!(entry, attempts, index)
          entry_id
        end
        unless entry_ids.uniq.length == entry_ids.length
          raise ContractError.new('entries.entry_id', 'must be unique')
        end
        findings = Value.fetch(journal, :findings)
        raise ContractError.new('findings', 'must be an array') unless findings.is_a?(Array)
        summary = Value.fetch(journal, :summary)
        raise ContractError.new('summary', 'must be a hash') unless summary.is_a?(Hash)
        Value.require_one_of!(
          'status',
          Value.fetch(journal, :status),
          OperationJournal::STATUSES
        )
        expected_rollup = rollup(entries)
        require_equal!('status', Value.fetch(journal, :status), expected_rollup.fetch(:status))
        expected_rollup.fetch(:summary).each do |key, expected|
          next if key.to_s.start_with?('verification_') && Value.fetch(summary, key).nil?

          require_equal!("summary.#{key}", Value.fetch(summary, key), expected)
        end

        expected_id = OperationJournal.journal_id_for(
          provider: provider,
          service: service,
          plan: plan,
          entries: entries
        )
        require_equal!('journal_id', Value.fetch(journal, :journal_id), expected_id)
        credential_paths = CredentialScanner.paths(journal, 'journal')
        unless credential_paths.empty?
          raise ContractError.new(credential_paths.first, 'credential-like keys are forbidden')
        end
      end

      def validate_attempts!(entry, attempts, index)
        attempts.each_with_index do |attempt, attempt_index|
          path = "entries[#{index}].attempts[#{attempt_index}]"
          raise ContractError.new(path, 'must be a hash') unless attempt.is_a?(Hash)
          unless Value.fetch(attempt, :attempt) == attempt_index + 1
            raise ContractError.new("#{path}.attempt", 'must be sequential')
          end
          attempt_status = Value.fetch(attempt, :status)
          Value.require_one_of!("#{path}.status", attempt_status, %w[running succeeded failed])
          validate_timestamp!("#{path}.started_at", Value.fetch(attempt, :started_at))
          if %w[succeeded failed].include?(attempt_status)
            validate_timestamp!("#{path}.finished_at", Value.fetch(attempt, :finished_at))
          elsif Value.fetch(attempt, :finished_at)
            raise ContractError.new("#{path}.finished_at", 'must be absent while running')
          end
          if attempt_status == 'failed' && !Value.fetch(attempt, :error).is_a?(Hash)
            raise ContractError.new("#{path}.error", 'must be a hash for a failed attempt')
          end
          if attempt_index < attempts.length - 1 && attempt_status == 'running'
            raise ContractError.new("#{path}.status", 'only the latest attempt may be running')
          end
        end

        entry_status = Value.fetch(entry, :status)
        expected_attempt_status = {
          'running' => 'running',
          'succeeded' => 'succeeded',
          'failed' => 'failed'
        }[entry_status]
        if expected_attempt_status && Value.fetch(attempts.last, :status) != expected_attempt_status
          raise ContractError.new(
            "entries[#{index}].attempts",
            "#{entry_status} requires a matching latest attempt"
          )
        end
        if %w[pending skipped].include?(entry_status) && !attempts.empty?
          raise ContractError.new(
            "entries[#{index}].attempts",
            "must be empty while entry status is #{entry_status}"
          )
        end
      end

      def validate_timestamp!(path, value)
        Value.require_presence!(path, value)
        Time.iso8601(value.to_s)
      rescue ArgumentError
        raise ContractError.new(path, 'must be an ISO 8601 timestamp')
      end

      def validate_fingerprint!(path, value)
        return if value.to_s.match?(/\A[0-9a-f]{64}\z/)

        raise ContractError.new(path, 'must be a SHA-256 fingerprint')
      end

      def validate_plan_reference!(plan)
        raise ContractError.new('plan', 'must be a hash') unless plan.is_a?(Hash)

        require_equal!('plan.schema_version', Value.fetch(plan, :schema_version), SCHEMA_VERSION)
        require_equal!('plan.kind', Value.fetch(plan, :kind), 'ProviderStatePlanReference')
        Value.require_one_of!('plan.mode', Value.fetch(plan, :mode), %w[dry_run live])
        %i[fingerprint desired_state_fingerprint observed_state_fingerprint].each do |key|
          value = required("plan.#{key}", plan, key)
          next if value.to_s.match?(/\A[0-9a-f]{64}\z/)

          raise ContractError.new("plan.#{key}", 'must be a SHA-256 fingerprint')
        end
        approved_plan = Value.fetch(plan, :approved_plan)
        validate_approved_plan_reference!(approved_plan) if approved_plan
      end

      def validate_approved_plan_reference!(reference)
        unless reference.is_a?(Hash)
          raise ContractError.new('plan.approved_plan', 'must be a hash')
        end
        require_equal!(
          'plan.approved_plan.schema_version',
          Value.fetch(reference, :schema_version),
          ApprovedPlan::SCHEMA_VERSION
        )
        require_equal!(
          'plan.approved_plan.kind',
          Value.fetch(reference, :kind),
          'ApprovedProviderPlanReference'
        )
        approved_plan_id = required(
          'plan.approved_plan.approved_plan_id',
          reference,
          :approved_plan_id
        )
        unless approved_plan_id.to_s.match?(/\Aapproved-provider-plan-[0-9a-f]{64}\z/)
          raise ContractError.new(
            'plan.approved_plan.approved_plan_id',
            'must be a content-addressed approved-plan identity'
          )
        end
        source_bundle_id = required(
          'plan.approved_plan.source_bundle_id',
          reference,
          :source_bundle_id
        )
        unless source_bundle_id.to_s.match?(/\Aslo-bundle-[0-9a-f]{64}\z/)
          raise ContractError.new(
            'plan.approved_plan.source_bundle_id',
            'must be a content-addressed release-bundle identity'
          )
        end
        %i[provider_plan_fingerprint evidence_fingerprint].each do |key|
          value = required("plan.approved_plan.#{key}", reference, key)
          next if value.to_s.match?(/\A[0-9a-f]{64}\z/)

          raise ContractError.new("plan.approved_plan.#{key}", 'must be a SHA-256 fingerprint')
        end
      end

      def validate_resume_policy!(resume_policy, index)
        path = "entries[#{index}].resume"
        raise ContractError.new(path, 'must be a hash') unless resume_policy.is_a?(Hash)
        unless [true, false].include?(Value.fetch(resume_policy, :eligible))
          raise ContractError.new("#{path}.eligible", 'must be true or false')
        end
        unless [true, false].include?(Value.fetch(resume_policy, :requires_state_recheck))
          raise ContractError.new("#{path}.requires_state_recheck", 'must be true or false')
        end
        Value.require_one_of!(
          "#{path}.classification",
          Value.fetch(resume_policy, :classification),
          OperationJournal::RESUME_CLASSIFICATIONS
        )
        reasons = Value.fetch(resume_policy, :reasons)
        raise ContractError.new("#{path}.reasons", 'must be an array') unless reasons.is_a?(Array)
      end

      def validate_verification_policy!(verification, index)
        path = "entries[#{index}].verification"
        raise ContractError.new(path, 'must be a hash') unless verification.is_a?(Hash)
        unless [true, false].include?(Value.fetch(verification, :required))
          raise ContractError.new("#{path}.required", 'must be true or false')
        end
        Value.require_one_of!(
          "#{path}.status",
          Value.fetch(verification, :status),
          OperationJournal::VERIFICATION_STATUSES
        )
        requirements = Value.fetch(verification, :requirements)
        raise ContractError.new("#{path}.requirements", 'must be an array') unless requirements.is_a?(Array)
        status = Value.fetch(verification, :status)
        required = Value.fetch(verification, :required)
        if !required && status != 'not_required'
          raise ContractError.new("#{path}.status", 'must be not_required when verification is not required')
        end
        if required && status == 'not_required'
          raise ContractError.new("#{path}.status", 'cannot be not_required when verification is required')
        end
        return if status == 'pending' || status == 'not_required'

        validate_timestamp!("#{path}.checked_at", Value.fetch(verification, :checked_at))
        required("#{path}.path", verification, :path)
        expected = validate_verification_state!(verification, :expected, path)
        actual = validate_verification_state!(verification, :actual, path)
        findings = Value.fetch(verification, :findings)
        raise ContractError.new("#{path}.findings", 'must be an array') unless findings.is_a?(Array)
        if status == 'succeeded' && expected.fetch(:fingerprint) != actual.fetch(:fingerprint)
          raise ContractError.new("#{path}.status", 'cannot succeed when state fingerprints differ')
        end
        if status == 'failed' && expected.fetch(:fingerprint) == actual.fetch(:fingerprint)
          raise ContractError.new("#{path}.status", 'cannot fail when state fingerprints match')
        end
        if status == 'failed' && findings.empty?
          raise ContractError.new("#{path}.findings", 'must describe a failed verification')
        end
      end

      def validate_verification_state!(verification, key, path)
        state = Value.fetch(verification, key)
        state_path = "#{path}.#{key}"
        raise ContractError.new(state_path, 'must be a hash') unless state.is_a?(Hash)
        unless [true, false].include?(Value.fetch(state, :present))
          raise ContractError.new("#{state_path}.present", 'must be true or false')
        end
        validate_fingerprint!("#{state_path}.fingerprint", Value.fetch(state, :fingerprint))
        state
      end

      def effective_status(counts)
        return 'partial' if counts.fetch('failed').positive? && counts.fetch('succeeded').positive?
        return 'failed' if counts.fetch('failed').positive?
        return 'running' if counts.fetch('running').positive? || (
          counts.fetch('succeeded').positive? && counts.fetch('pending').positive?
        )
        return 'pending' if counts.fetch('pending').positive?

        'succeeded'
      end

      def runtime_findings(provider, status, failed, blocked, failed_verifications)
        findings = []
        if status == 'partial'
          findings << Finding.new(
            provider: provider,
            code: 'partial_failure',
            severity: 'error',
            message: 'some operations succeeded before another operation failed',
            evidence: { failed_entries: failed.map { |entry| Value.fetch(entry, :entry_id) } }
          ).to_h
        end
        if blocked.any?
          findings << Finding.new(
            provider: provider,
            code: 'resume_blocked',
            severity: 'error',
            message: 'failed operations require manual verification before retry',
            evidence: { blocked_entries: blocked.map { |entry| Value.fetch(entry, :entry_id) } }
          ).to_h
        elsif failed.any?
          findings << Finding.new(
            provider: provider,
            code: 'resume_state_recheck_required',
            severity: 'warning',
            message: 'failed operations may be retried only after provider state is refreshed',
            evidence: { failed_entries: failed.map { |entry| Value.fetch(entry, :entry_id) } }
          ).to_h
        end
        failed_verifications.each do |entry|
          verification = Value.fetch(entry, :verification)
          findings << Finding.new(
            provider: provider,
            code: 'post_apply_verification_failed',
            severity: 'error',
            message: 'managed resource does not match the expected post-apply state',
            target: Value.fetch(entry, :target),
            source: Value.fetch(entry, :source),
            evidence: {
              entry_id: Value.fetch(entry, :entry_id),
              path: Value.fetch(verification, :path),
              expected_fingerprint: Value.fetch(Value.fetch(verification, :expected), :fingerprint),
              actual_fingerprint: Value.fetch(Value.fetch(verification, :actual), :fingerprint),
              finding_codes: Array(Value.fetch(verification, :findings)).map do |finding|
                Value.fetch(finding, :code)
              end
            }
          ).to_h
        end
        findings
      end

      def required(path, container, key = nil)
        value = Value.fetch(container, key || path)
        Value.require_presence!(path, value)
        value
      end

      def require_equal!(path, actual, expected)
        return if actual == expected

        raise ContractError.new(path, "must equal #{expected.inspect}")
      end
    end
  end
end
