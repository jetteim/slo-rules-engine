# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/slo_rules_engine'

class ProviderStateJournalTransitionTest < Minitest::Test
  STARTED_AT = '2026-07-26T12:00:00.000000Z'
  FINISHED_AT = '2026-07-26T12:00:01.000000Z'

  def test_transitioner_records_one_legal_attempt_without_changing_journal_identity
    initial = operation_journal
    entry_id = initial.fetch(:entries).fetch(0).fetch(:entry_id)
    transitioner = SloRulesEngine::ProviderState::JournalTransitioner.new

    running = transitioner.transition(
      initial,
      entry_id: entry_id,
      to: 'running',
      occurred_at: STARTED_AT
    )
    succeeded = transitioner.transition(
      running,
      entry_id: entry_id,
      to: 'succeeded',
      occurred_at: FINISHED_AT,
      evidence: {
        provider_resource_id: '/managed/checkout-api/prometheus_stack/manifest.json',
        bytes_written: 512
      }
    )

    assert_equal initial.fetch(:journal_id), succeeded.fetch(:journal_id)
    assert_equal 'succeeded', succeeded.fetch(:status)
    entry = succeeded.fetch(:entries).fetch(0)
    assert_equal 'succeeded', entry.fetch(:status)
    assert_equal 1, entry.fetch(:attempts).length
    assert_equal STARTED_AT, entry.dig(:attempts, 0, :started_at)
    assert_equal FINISHED_AT, entry.dig(:attempts, 0, :finished_at)
    assert_equal 512, entry.dig(:attempts, 0, :result, :bytes_written)
    assert_equal 1, succeeded.dig(:summary, :succeeded_entries)
  end

  def test_transitioner_rejects_terminal_transition_without_running_attempt
    initial = operation_journal
    entry_id = initial.fetch(:entries).fetch(0).fetch(:entry_id)

    error = assert_raises(SloRulesEngine::ProviderState::ContractError) do
      SloRulesEngine::ProviderState::JournalTransitioner.new.transition(
        initial,
        entry_id: entry_id,
        to: 'succeeded',
        occurred_at: FINISHED_AT
      )
    end

    assert_equal 'entries[0].status', error.path
    assert_includes error.message, 'pending cannot transition to succeeded'
  end

  def test_evaluator_rejects_a_terminal_status_without_matching_attempt_evidence
    journal = operation_journal
    journal[:entries][0][:status] = 'succeeded'

    status = SloRulesEngine::ProviderState::JournalEvaluator.new.evaluate(journal)

    assert_equal false, status.fetch(:valid)
    assert_equal 'entries[0].attempts', status.fetch(:findings).fetch(0).fetch(:path)
  end

  def test_evaluator_rejects_stale_top_level_status_and_summary
    stale_status = operation_journal
    stale_status[:status] = 'succeeded'

    status_result = SloRulesEngine::ProviderState::JournalEvaluator.new.evaluate(stale_status)

    assert_equal false, status_result.fetch(:valid)
    assert_equal 'status', status_result.fetch(:findings).fetch(0).fetch(:path)

    stale_summary = operation_journal
    stale_summary[:summary][:pending_entries] = 99

    summary_result = SloRulesEngine::ProviderState::JournalEvaluator.new.evaluate(stale_summary)

    assert_equal false, summary_result.fetch(:valid)
    assert_equal 'summary.pending_entries', summary_result.fetch(:findings).fetch(0).fetch(:path)
  end

  def test_evaluator_accepts_v1_journal_without_additive_verification_rollups
    journal = operation_journal
    journal.fetch(:summary).delete_if { |key, _value| key.to_s.start_with?('verification_') }

    result = SloRulesEngine::ProviderState::JournalEvaluator.new.evaluate(journal)

    assert_equal true, result.fetch(:valid)
    assert_equal 1, result.dig(:summary, :verification_pending_entries)
  end

  def test_transitioner_rejects_credential_like_attempt_evidence
    initial = operation_journal
    entry_id = initial.fetch(:entries).fetch(0).fetch(:entry_id)

    error = assert_raises(SloRulesEngine::ProviderState::ContractError) do
      SloRulesEngine::ProviderState::JournalTransitioner.new.transition(
        initial,
        entry_id: entry_id,
        to: 'running',
        occurred_at: STARTED_AT,
        evidence: {
          token: 'must-not-be-journaled'
        }
      )
    end

    assert_equal 'journal.entries[0].attempts[0].evidence.token', error.path
  end

  def test_transitioner_records_failure_and_can_skip_unstarted_following_work
    initial = operation_journal(change_count: 2)
    first_id, second_id = initial.fetch(:entries).map { |entry| entry.fetch(:entry_id) }
    transitioner = SloRulesEngine::ProviderState::JournalTransitioner.new

    running = transitioner.transition(
      initial,
      entry_id: first_id,
      to: 'running',
      occurred_at: STARTED_AT
    )
    failed = transitioner.transition(
      running,
      entry_id: first_id,
      to: 'failed',
      occurred_at: FINISHED_AT,
      evidence: {
        error: {
          code: 'file_write_failed',
          class: 'Errno::EACCES',
          message: 'permission denied'
        }
      }
    )
    stopped = transitioner.transition(
      failed,
      entry_id: second_id,
      to: 'skipped',
      occurred_at: FINISHED_AT,
      evidence: {
        reason: 'prior_operation_failed'
      }
    )

    assert_equal %w[failed skipped], stopped.fetch(:entries).map { |entry| entry.fetch(:status) }
    assert_equal 'failed', stopped.fetch(:status)
    assert_equal 'file_write_failed', stopped.dig(:entries, 0, :attempts, 0, :error, :code)
    assert_equal 'prior_operation_failed', stopped.dig(:entries, 1, :skip, :reason)
  end

  def test_store_creates_and_transitions_a_journal_atomically
    Dir.mktmpdir do |dir|
      store = SloRulesEngine::ProviderState::JournalStore.new(
        root_dir: dir,
        clock: -> { Time.utc(2026, 7, 26, 12, 0, 0) }
      )
      initial = operation_journal
      path = store.create(initial)
      entry_id = initial.fetch(:entries).fetch(0).fetch(:entry_id)

      updated = store.transition(path, entry_id: entry_id, to: 'running')
      persisted = JSON.parse(File.read(path), symbolize_names: true)

      assert_equal File.join(
        dir,
        'checkout-api',
        'prometheus_stack',
        "#{initial.fetch(:journal_id)}.json"
      ), path
      assert_equal updated, persisted
      assert_equal 'running', persisted.fetch(:status)
      assert_equal STARTED_AT, persisted.dig(:entries, 0, :attempts, 0, :started_at)
      assert_raises(SloRulesEngine::ProviderState::JournalConflict) { store.create(initial) }
    end
  end

  def test_store_serializes_competing_transitions
    Dir.mktmpdir do |dir|
      store = SloRulesEngine::ProviderState::JournalStore.new(
        root_dir: dir,
        clock: -> { Time.utc(2026, 7, 26, 12, 0, 0) }
      )
      initial = operation_journal
      path = store.create(initial)
      entry_id = initial.fetch(:entries).fetch(0).fetch(:entry_id)
      outcomes = Queue.new

      threads = 2.times.map do
        Thread.new do
          outcomes << store.transition(path, entry_id: entry_id, to: 'running')
        rescue SloRulesEngine::ProviderState::ContractError => error
          outcomes << error
        end
      end
      threads.each(&:join)
      values = 2.times.map { outcomes.pop }
      persisted = store.read(path)

      assert_equal 1, values.count { |value| value.is_a?(Hash) }
      assert_equal 1, values.count { |value| value.is_a?(SloRulesEngine::ProviderState::ContractError) }
      assert_equal 'running', persisted.dig(:entries, 0, :status)
      assert_equal 1, persisted.dig(:entries, 0, :attempts).length
    end
  end

  def test_store_records_terminal_verification_evidence_once
    Dir.mktmpdir do |dir|
      store = SloRulesEngine::ProviderState::JournalStore.new(
        root_dir: dir,
        clock: -> { Time.utc(2026, 7, 26, 12, 0, 0) }
      )
      initial = operation_journal
      path = store.create(initial)
      entry_id = initial.fetch(:entries).fetch(0).fetch(:entry_id)
      fingerprint = 'a' * 64

      updated = store.record_verification(
        path,
        entry_id: entry_id,
        evidence: {
          status: 'succeeded',
          path: '/managed/manifest.json',
          expected: { present: true, fingerprint: fingerprint },
          actual: { present: true, fingerprint: fingerprint },
          findings: []
        }
      )

      assert_equal 'succeeded', updated.dig(:entries, 0, :verification, :status)
      assert_equal STARTED_AT, updated.dig(:entries, 0, :verification, :checked_at)
      assert_equal 1, updated.dig(:summary, :verification_succeeded_entries)
      error = assert_raises(SloRulesEngine::ProviderState::ContractError) do
        store.record_verification(
          path,
          entry_id: entry_id,
          evidence: {
            status: 'failed',
            path: '/managed/manifest.json',
            expected: { present: true, fingerprint: fingerprint },
            actual: { present: false, fingerprint: 'b' * 64 },
            findings: [{ code: 'managed_file_missing_after_write' }]
          }
        )
      end
      assert_equal 'entries[0].verification.status', error.path
    end
  end

  def test_result_builder_links_operation_outcomes_to_the_plan
    state_plan = provider_plan(mode: 'live')
    initial = SloRulesEngine::ProviderState::JournalBuilder.new(
      accepted_modes: ['live']
    ).build(state_plan).to_h
    entry_id = initial.fetch(:entries).fetch(0).fetch(:entry_id)
    transitioner = SloRulesEngine::ProviderState::JournalTransitioner.new
    running = transitioner.transition(
      initial,
      entry_id: entry_id,
      to: 'running',
      occurred_at: STARTED_AT
    )
    succeeded = transitioner.transition(
      running,
      entry_id: entry_id,
      to: 'succeeded',
      occurred_at: FINISHED_AT,
      evidence: {
        provider_resource_id: '/managed/checkout-api/prometheus_stack/manifest.json'
      }
    )

    result = SloRulesEngine::ProviderState::ResultBuilder.new.build(
      plan: state_plan,
      journal: succeeded
    ).to_h

    assert_equal 'ProviderStateResult', result.fetch(:kind)
    assert_equal 'succeeded', result.fetch(:status)
    assert_equal state_plan.fingerprint, result.fetch(:plan_fingerprint)
    assert_equal '/managed/checkout-api/prometheus_stack/manifest.json',
                 result.dig(:operation_results, 0, :provider_resource_id)
    assert_equal 'pending', result.dig(:verification, :status)
    assert_includes result.dig(:verification, :requirements), 'refresh_managed_file_state'
  end

  private

  def operation_journal(change_count: 1)
    SloRulesEngine::ProviderState::JournalBuilder.new.build(
      provider_plan(change_count: change_count)
    ).to_h
  end

  def provider_plan(change_count: 1, mode: 'dry_run')
    desired = SloRulesEngine::ProviderState::DesiredState.new(
      provider: 'prometheus_stack',
      service: 'checkout-api',
      source: 'provider_manifest',
      resources: {
        manifest: {
          provider: 'prometheus_stack'
        }
      }
    )
    observed = SloRulesEngine::ProviderState::ObservedState.new(
      provider: 'prometheus_stack',
      service: 'checkout-api',
      source: 'manifest_bundle',
      resources: {
        files: []
      }
    )
    changes = change_count.times.map do |index|
      SloRulesEngine::ProviderState::Change.new(
        action: 'write',
        target: index.zero? ? 'manifest_file' : 'prometheus_stack.prometheus_rule',
        name: index.zero? ? 'manifest.json' : 'prometheus-rules.yaml',
        source: index.zero? ? 'manifest' : 'artifacts.prometheus_rule_resources[0]',
        desired: {
          path: index.zero? ? '/managed/manifest.json' : '/managed/prometheus-rules.yaml'
        },
        changed_paths: ['content']
      )
    end
    SloRulesEngine::ProviderState::Plan.new(
      provider: 'prometheus_stack',
      service: 'checkout-api',
      mode: mode,
      desired_state: desired,
      observed_state: observed,
      changes: changes,
      findings: [],
      summary: {
        total_operations: changes.length,
        actionable_operations: changes.length,
        destructive_operations: 0
      }
    )
  end
end
