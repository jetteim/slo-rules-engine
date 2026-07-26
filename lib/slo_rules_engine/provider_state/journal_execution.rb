# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'tempfile'
require 'time'

module SloRulesEngine
  module ProviderState
    class JournalConflict < StandardError
      attr_reader :path

      def initialize(path)
        @path = path
        super("operation journal already exists at #{path}")
      end
    end

    class JournalTransitioner
      TRANSITIONS = {
        'pending' => %w[running skipped],
        'running' => %w[succeeded failed],
        'succeeded' => [],
        'failed' => [],
        'skipped' => []
      }.freeze

      def transition(journal, entry_id:, to:, occurred_at:, evidence: {})
        current = validated_copy(journal)
        entries = Value.fetch(current, :entries)
        index = entries.index { |entry| Value.fetch(entry, :entry_id) == entry_id }
        raise ContractError.new('entry_id', 'does not identify a journal entry') unless index

        entry = entries.fetch(index)
        from = Value.fetch(entry, :status)
        Value.require_one_of!('status', to, OperationJournal::ENTRY_STATUSES)
        unless TRANSITIONS.fetch(from).include?(to)
          raise ContractError.new(
            "entries[#{index}].status",
            "#{from} cannot transition to #{to}"
          )
        end

        evidence = Value.copy(evidence || {})
        case to
        when 'running'
          start_attempt!(entry, occurred_at, evidence)
        when 'succeeded'
          finish_attempt!(entry, occurred_at, 'succeeded', evidence, index)
        when 'failed'
          finish_attempt!(entry, occurred_at, 'failed', evidence, index)
        when 'skipped'
          entry[:skip] = evidence.merge(occurred_at: occurred_at)
        end
        entry[:status] = to
        refresh_rollups!(current)
        current
      end

      def record_verification(journal, entry_id:, occurred_at:, evidence:)
        current = validated_copy(journal)
        entries = Value.fetch(current, :entries)
        index = entries.index { |entry| Value.fetch(entry, :entry_id) == entry_id }
        raise ContractError.new('entry_id', 'does not identify a journal entry') unless index

        entry = entries.fetch(index)
        verification = Value.fetch(entry, :verification)
        unless Value.fetch(verification, :required)
          raise ContractError.new(
            "entries[#{index}].verification.required",
            'must be true before verification can be recorded'
          )
        end
        unless Value.fetch(verification, :status) == 'pending'
          raise ContractError.new(
            "entries[#{index}].verification.status",
            'must be pending before terminal evidence is recorded'
          )
        end

        evidence = Value.copy(evidence || {})
        Value.require_one_of!('verification.status', Value.fetch(evidence, :status), %w[succeeded failed])
        entry[:verification] = verification.merge(evidence).merge(checked_at: occurred_at)
        refresh_rollups!(current)
        current
      end

      private

      def validated_copy(journal)
        evaluation = JournalEvaluator.new.evaluate(journal)
        return JSON.parse(JSON.generate(journal), symbolize_names: true) if evaluation[:valid]

        finding = evaluation.fetch(:findings).fetch(0)
        raise ContractError.new(
          Value.fetch(finding, :path) || 'journal',
          Value.fetch(finding, :message)
        )
      end

      def start_attempt!(entry, occurred_at, evidence)
        attempts = Value.fetch(entry, :attempts)
        attempt = {
          attempt: attempts.length + 1,
          status: 'running',
          started_at: occurred_at
        }
        attempt[:evidence] = evidence unless evidence.empty?
        attempts << attempt
      end

      def finish_attempt!(entry, occurred_at, status, evidence, index)
        attempt = Value.fetch(entry, :attempts).last
        unless attempt && Value.fetch(attempt, :status) == 'running'
          raise ContractError.new(
            "entries[#{index}].attempts",
            "#{status} requires a running attempt"
          )
        end

        attempt[:status] = status
        attempt[:finished_at] = occurred_at
        if status == 'failed'
          error = Value.fetch(evidence, :error)
          raise ContractError.new("entries[#{index}].attempts.error", 'is required') unless error.is_a?(Hash)

          attempt[:error] = error
        elsif !evidence.empty?
          attempt[:result] = evidence
        end
      end

      def refresh_rollups!(journal)
        evaluator = JournalEvaluator.new
        rollup = evaluator.rollup(Value.fetch(journal, :entries))
        journal[:status] = rollup.fetch(:status)
        journal[:summary] = Value.fetch(journal, :summary).merge(rollup.fetch(:summary))
        evaluation = evaluator.evaluate(journal)
        unless evaluation[:valid]
          finding = evaluation.fetch(:findings).fetch(0)
          raise ContractError.new(
            Value.fetch(finding, :path) || 'journal',
            Value.fetch(finding, :message)
          )
        end
      end
    end

    class JournalStore
      attr_reader :root_dir

      def initialize(root_dir:, clock: -> { Time.now.utc }, transitioner: JournalTransitioner.new)
        Value.require_presence!('root_dir', root_dir)
        @root_dir = File.expand_path(root_dir)
        @clock = clock
        @transitioner = transitioner
      end

      def create(journal)
        payload = journal.respond_to?(:to_h) ? journal.to_h : Value.copy(journal)
        validate!(payload)
        path = path_for(payload)
        with_lock(path) do
          if File.exist?(path)
            existing = JSON.parse(File.read(path), symbolize_names: true)
            if noop_journal?(payload) && Fingerprint.content(existing) == Fingerprint.content(payload)
              return path
            end

            raise JournalConflict, path
          end

          write_atomic(path, payload)
        end
        path
      end

      def transition(path, entry_id:, to:, evidence: {})
        with_lock(path) do
          current = JSON.parse(File.read(path), symbolize_names: true)
          updated = @transitioner.transition(
            current,
            entry_id: entry_id,
            to: to,
            occurred_at: timestamp,
            evidence: evidence
          )
          write_atomic(path, updated)
          updated
        end
      end

      def record_verification(path, entry_id:, evidence:)
        with_lock(path) do
          current = JSON.parse(File.read(path), symbolize_names: true)
          occurred_at = Value.fetch(evidence, :checked_at) || timestamp
          updated = @transitioner.record_verification(
            current,
            entry_id: entry_id,
            occurred_at: occurred_at,
            evidence: evidence
          )
          write_atomic(path, updated)
          updated
        end
      end

      def read(path)
        JSON.parse(File.read(path), symbolize_names: true)
      end

      def path_for(journal)
        File.join(
          root_dir,
          safe_component(Value.fetch(journal, :service)),
          safe_component(Value.fetch(journal, :provider)),
          "#{Value.fetch(journal, :journal_id)}.json"
        )
      end

      private

      def validate!(journal)
        evaluation = JournalEvaluator.new.evaluate(journal)
        return if evaluation[:valid]

        finding = evaluation.fetch(:findings).fetch(0)
        raise ContractError.new(
          Value.fetch(finding, :path) || 'journal',
          Value.fetch(finding, :message)
        )
      end

      def timestamp
        @clock.call.utc.iso8601(6)
      end

      def safe_component(value)
        component = value.to_s.gsub(/[^A-Za-z0-9._-]/, '_')
        Value.require_presence!('journal path component', component)
        component
      end

      def noop_journal?(journal)
        entries = Value.fetch(journal, :entries)
        !entries.empty? && entries.all? { |entry| Value.fetch(entry, :status) == 'skipped' }
      end

      def with_lock(path)
        FileUtils.mkdir_p(File.dirname(path))
        File.open("#{path}.lock", File::RDWR | File::CREAT, 0o600) do |lock|
          lock.flock(File::LOCK_EX)
          yield
        ensure
          lock.flock(File::LOCK_UN)
        end
      end

      def write_atomic(path, payload)
        Tempfile.create(['.operation-journal-', '.tmp'], File.dirname(path)) do |file|
          file.write(JSON.pretty_generate(payload))
          file.write("\n")
          file.flush
          file.fsync
          file.close
          File.rename(file.path, path)
        end
      end
    end

    class ResultBuilder
      def build(plan:, journal:)
        raise ContractError.new('plan', 'must be a ProviderStatePlan') unless plan.is_a?(Plan)
        raise ContractError.new('plan.mode', 'must be live for an execution result') unless plan.mode == 'live'

        evaluation = JournalEvaluator.new.evaluate(journal)
        unless evaluation[:valid]
          finding = evaluation.fetch(:findings).fetch(0)
          raise ContractError.new(
            Value.fetch(finding, :path) || 'journal',
            Value.fetch(finding, :message)
          )
        end
        require_plan_identity!(plan, journal)
        verification = verification(journal)

        Result.new(
          provider: plan.provider,
          service: plan.service,
          mode: 'live',
          status: result_status(evaluation, journal, verification),
          desired_state_fingerprint: plan.desired_state.fingerprint,
          observed_state_fingerprint: plan.observed_state.fingerprint,
          plan_fingerprint: plan.fingerprint,
          operation_results: operation_results(journal),
          findings: evaluation.fetch(:findings).map do |finding|
            Finding.from_hash(finding, provider: plan.provider)
          end,
          verification: verification
        )
      end

      private

      def require_plan_identity!(plan, journal)
        reference = Value.fetch(journal, :plan)
        {
          fingerprint: plan.fingerprint,
          desired_state_fingerprint: plan.desired_state.fingerprint,
          observed_state_fingerprint: plan.observed_state.fingerprint
        }.each do |key, expected|
          next if Value.fetch(reference, key) == expected

          raise ContractError.new("journal.plan.#{key}", 'must match result plan')
        end
      end

      def result_status(evaluation, journal, verification)
        case evaluation.fetch(:status)
        when 'succeeded'
          entries = Value.fetch(journal, :entries)
          return 'noop' unless entries.any? { |entry| Value.fetch(entry, :status) == 'succeeded' }

          verification.fetch(:status) == 'failed' ? 'failed' : 'succeeded'
        when 'partial' then 'partial'
        when 'failed' then 'failed'
        else 'blocked'
        end
      end

      def operation_results(journal)
        Value.fetch(journal, :entries).map do |entry|
          latest_attempt = Value.fetch(entry, :attempts).last
          result = latest_attempt && Value.fetch(latest_attempt, :result)
          Value.compact(
            entry_id: Value.fetch(entry, :entry_id),
            action: Value.fetch(entry, :action),
            target: Value.fetch(entry, :target),
            name: Value.fetch(entry, :name),
            status: Value.fetch(entry, :status),
            provider_resource_id: Value.fetch(result, :provider_resource_id) ||
              Value.fetch(entry, :provider_resource_id),
            attempts: Value.copy(Value.fetch(entry, :attempts)),
            skip: Value.copy(Value.fetch(entry, :skip)),
            verification: Value.copy(Value.fetch(entry, :verification))
          )
        end
      end

      def verification(journal)
        entries = Value.fetch(journal, :entries)
        resources = entries.filter_map do |entry|
          entry_verification = Value.fetch(entry, :verification)
          next unless Value.fetch(entry_verification, :required)

          Value.compact(
            entry_id: Value.fetch(entry, :entry_id),
            target: Value.fetch(entry, :target),
            name: Value.fetch(entry, :name),
            source: Value.fetch(entry, :source),
            status: Value.fetch(entry_verification, :status),
            checked_at: Value.fetch(entry_verification, :checked_at),
            path: Value.fetch(entry_verification, :path),
            expected: Value.copy(Value.fetch(entry_verification, :expected)),
            actual: Value.copy(Value.fetch(entry_verification, :actual)),
            findings: Value.copy(Value.fetch(entry_verification, :findings))
          )
        end
        statuses = entries.map do |entry|
          Value.fetch(Value.fetch(entry, :verification), :status)
        end
        {
          status: verification_status(entries),
          engine_owned_status: verification_status(
            entries.reject { |entry| Value.fetch(entry, :target) == 'external_generator' }
          ),
          external_status: verification_status(
            entries.select { |entry| Value.fetch(entry, :target) == 'external_generator' }
          ),
          checked_at: resources.filter_map { |resource| Value.fetch(resource, :checked_at) }.max,
          requirements: entries.flat_map do |entry|
            Array(Value.fetch(Value.fetch(entry, :verification), :requirements))
          end.uniq,
          summary: {
            required_resources: resources.length,
            pending_resources: statuses.count('pending'),
            succeeded_resources: statuses.count('succeeded'),
            failed_resources: statuses.count('failed'),
            not_required_resources: statuses.count('not_required')
          },
          resources: resources
        }
      end

      def verification_status(entries)
        required = entries.select do |entry|
          Value.fetch(Value.fetch(entry, :verification), :required)
        end
        return 'not_required' if required.empty?

        statuses = required.map do |entry|
          Value.fetch(Value.fetch(entry, :verification), :status)
        end
        return 'failed' if statuses.include?('failed')
        return 'pending' if statuses.include?('pending')

        'succeeded'
      end
    end

    class JournaledExecutor
      def initialize(
        journal_store: nil,
        clock: -> { Time.now.utc },
        verifier: ManagedFileVerifier.new,
        error_evidence: nil
      )
        @journal_store = journal_store
        @clock = clock
        @transitioner = JournalTransitioner.new
        @verifier = verifier
        @error_evidence = error_evidence || method(:file_error_evidence)
      end

      def execute(apply_plan)
        plan = apply_plan.provider_state_plan
        raise ContractError.new('plan', 'must include provider state') unless plan
        raise ContractError.new('plan.mode', 'must be live for execution') unless plan.mode == 'live'

        journal = JournalBuilder.new(accepted_modes: ['live']).build(plan).to_h
        journal_path = @journal_store&.create(journal)
        failed = false

        apply_plan.operations.each_with_index do |operation, index|
          entry = Value.fetch(journal, :entries).fetch(index)
          entry_id = Value.fetch(entry, :entry_id)
          next if operation.action == 'noop'

          if failed
            journal = transition(
              journal,
              journal_path,
              entry_id: entry_id,
              to: 'skipped',
              evidence: { reason: 'prior_operation_failed' }
            )
            next
          end
          if operation.action == 'handoff'
            journal = transition(
              journal,
              journal_path,
              entry_id: entry_id,
              to: 'skipped',
              evidence: { reason: 'external_handoff_required' }
            )
            next
          end

          journal = transition(journal, journal_path, entry_id: entry_id, to: 'running')
          begin
            outcome = yield(operation)
            journal = transition(
              journal,
              journal_path,
              entry_id: entry_id,
              to: 'succeeded',
              evidence: outcome || {}
            )
          rescue StandardError => error
            journal = transition(
              journal,
              journal_path,
              entry_id: entry_id,
              to: 'failed',
              evidence: { error: @error_evidence.call(error, operation) }
            )
            failed = true
          end
        end

        journal = verify_entries(plan, journal, journal_path)
        result = ResultBuilder.new.build(plan: plan, journal: journal)
        apply_plan.execution = {
          operation_journal: Value.compact(
            schema_version: JOURNAL_SCHEMA_VERSION,
            journal_id: Value.fetch(journal, :journal_id),
            path: journal_path,
            status: Value.fetch(journal, :status)
          ),
          result: result.to_h
        }
        apply_plan
      end

      private

      def verify_entries(plan, journal, path)
        entries = Value.fetch(journal, :entries).select do |entry|
          verification = Value.fetch(entry, :verification)
          next false unless Value.fetch(verification, :required)
          next false if Value.fetch(entry, :target) == 'external_generator'

          !@verifier.respond_to?(:verifiable?) || @verifier.verifiable?(entry)
        end
        return journal if entries.empty?

        context = if @verifier.respond_to?(:prepare)
                    @verifier.prepare(plan: plan, journal: journal)
                  end
        entries.each do |entry|
          evidence = verify_entry(entry, context)
          journal = record_verification(
            journal,
            path,
            entry_id: Value.fetch(entry, :entry_id),
            evidence: evidence
          )
        end
        journal
      end

      def verify_entry(entry, context)
        parameters = @verifier.method(:verify).parameters
        accepts_context = parameters.any? do |type, name|
          type == :keyrest || (name == :context && %i[key keyreq].include?(type))
        end
        return @verifier.verify(entry, checked_at: timestamp, context: context) if accepts_context

        @verifier.verify(entry, checked_at: timestamp)
      end

      def file_error_evidence(error, _operation)
        {
          code: 'file_operation_failed',
          class: error.class.name,
          message: error.message
        }
      end

      def record_verification(journal, path, entry_id:, evidence:)
        if @journal_store
          return @journal_store.record_verification(
            path,
            entry_id: entry_id,
            evidence: evidence
          )
        end

        @transitioner.record_verification(
          journal,
          entry_id: entry_id,
          occurred_at: Value.fetch(evidence, :checked_at),
          evidence: evidence
        )
      end

      def timestamp
        @clock.call.utc.iso8601(6)
      end

      def transition(journal, path, entry_id:, to:, evidence: {})
        if @journal_store
          return @journal_store.transition(
            path,
            entry_id: entry_id,
            to: to,
            evidence: evidence
          )
        end

        @transitioner.transition(
          journal,
          entry_id: entry_id,
          to: to,
          occurred_at: timestamp,
          evidence: evidence
        )
      end
    end
  end
end
