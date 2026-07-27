# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/slo_rules_engine'

class ProviderStateJournalTest < Minitest::Test
  def test_plan_loader_reconstructs_and_verifies_a_saved_plan
    plan = datadog_plan

    loaded = SloRulesEngine::ProviderState::PlanLoader.new.load(
      state_contract: plan.to_h
    )

    assert_equal plan.to_h, loaded.to_h
  end

  def test_plan_loader_rejects_tampered_snapshot_content
    payload = datadog_plan.to_h
    payload[:desired_state][:resources][:slos][0][:name] = 'tampered'

    error = assert_raises(SloRulesEngine::ProviderState::ContractError) do
      SloRulesEngine::ProviderState::PlanLoader.new.load(payload)
    end

    assert_equal 'desired_state.fingerprint', error.path
  end

  def test_plan_loader_rejects_tampered_plan_identity
    payload = datadog_plan.to_h
    payload[:fingerprint] = '0' * 64

    error = assert_raises(SloRulesEngine::ProviderState::ContractError) do
      SloRulesEngine::ProviderState::PlanLoader.new.load(payload)
    end

    assert_equal 'fingerprint', error.path
  end

  def test_journal_is_deterministic_and_preserves_datadog_execution_evidence
    builder = SloRulesEngine::ProviderState::JournalBuilder.new

    first = builder.build(datadog_plan)
    second = builder.build(datadog_plan)
    payload = first.to_h

    assert_equal 'slo-rules-engine/provider-operation-journal/v1', payload.fetch(:schema_version)
    assert_equal 'ProviderOperationJournal', payload.fetch(:kind)
    assert_equal first.journal_id, second.journal_id
    assert_equal first.to_h, second.to_h
    assert_equal 'pending', payload.fetch(:status)
    assert_equal datadog_plan.fingerprint, payload.dig(:plan, :fingerprint)
    assert_equal datadog_plan.desired_state.fingerprint, payload.dig(:plan, :desired_state_fingerprint)
    assert_equal datadog_plan.observed_state.fingerprint, payload.dig(:plan, :observed_state_fingerprint)

    recreate = payload.fetch(:entries).fetch(0)
    assert_equal 'pending', recreate.fetch(:status)
    assert_equal 'slo-123', recreate.fetch(:provider_resource_id)
    assert_equal 'source_ref', recreate.dig(:match_identity, :strategy)
    assert_equal 'high', recreate.dig(:risk, :level)
    assert_equal false, recreate.dig(:resume, :eligible)
    assert_equal 'manual_intervention_required', recreate.dig(:resume, :classification)
    assert_equal true, recreate.dig(:verification, :required)

    noop = payload.fetch(:entries).fetch(2)
    assert_equal 'skipped', noop.fetch(:status)
    assert_equal 'no_execution_required', noop.dig(:resume, :classification)
    assert_equal 'not_required', noop.dig(:verification, :status)
    assert_includes payload.fetch(:findings).map { |finding| finding.fetch(:code) }, 'non_resumable_operation'
  end

  def test_journal_preserves_prometheus_write_state_recheck_requirements
    journal = SloRulesEngine::ProviderState::JournalBuilder.new.build(prometheus_plan).to_h
    entry = journal.fetch(:entries).fetch(0)

    assert_equal 'prometheus_stack', journal.fetch(:provider)
    assert_equal 'write', entry.fetch(:action)
    assert_equal true, entry.dig(:resume, :eligible)
    assert_equal true, entry.dig(:resume, :requires_state_recheck)
    assert_equal 'retry_after_state_recheck', entry.dig(:resume, :classification)
    assert_equal ['refresh_managed_file_state', 'compare_desired_state'], entry.dig(:verification, :requirements)
  end

  def test_evaluator_validates_approved_plan_reference_integrity
    journal = SloRulesEngine::ProviderState::JournalBuilder.new.build(
      prometheus_plan,
      approved_plan_reference: {
        schema_version: 'slo-rules-engine/approved-provider-plan/v1',
        kind: 'ApprovedProviderPlanReference',
        approved_plan_id: "approved-provider-plan-#{'a' * 64}",
        provider_plan_fingerprint: 'b' * 64,
        source_bundle_id: "slo-bundle-#{'c' * 64}",
        evidence_fingerprint: 'd' * 64
      }
    ).to_h
    assert_equal "approved-provider-plan-#{'a' * 64}",
                 journal.dig(:plan, :approved_plan, :approved_plan_id)
    journal[:plan][:approved_plan][:provider_plan_fingerprint] = 'tampered'

    status = SloRulesEngine::ProviderState::JournalEvaluator.new.evaluate(journal)

    assert_equal false, status.fetch(:valid)
    assert_equal 'plan.approved_plan.provider_plan_fingerprint',
                 status.fetch(:findings).fetch(0).fetch(:path)
  end

  def test_evaluator_reports_partial_failure_and_blocks_non_resumable_retry
    journal = SloRulesEngine::ProviderState::JournalBuilder.new.build(datadog_plan).to_h
    first_id, second_id = journal.fetch(:entries).map { |entry| entry.fetch(:entry_id) }
    transitioner = SloRulesEngine::ProviderState::JournalTransitioner.new
    journal = transitioner.transition(
      journal,
      entry_id: first_id,
      to: 'running',
      occurred_at: '2026-07-26T12:00:00Z'
    )
    journal = transitioner.transition(
      journal,
      entry_id: first_id,
      to: 'failed',
      occurred_at: '2026-07-26T12:00:01Z',
      evidence: {
        error: {
          code: 'provider_request_failed',
          message: 'request outcome is unknown'
        }
      }
    )
    journal = transitioner.transition(
      journal,
      entry_id: second_id,
      to: 'running',
      occurred_at: '2026-07-26T12:00:02Z'
    )
    journal = transitioner.transition(
      journal,
      entry_id: second_id,
      to: 'succeeded',
      occurred_at: '2026-07-26T12:00:03Z'
    )

    status = SloRulesEngine::ProviderState::JournalEvaluator.new.evaluate(journal)

    assert_equal true, status.fetch(:valid)
    assert_equal 'partial', status.fetch(:status)
    assert_equal false, status.dig(:resume, :eligible)
    assert_equal 1, status.dig(:summary, :failed_entries)
    assert_equal 1, status.dig(:summary, :succeeded_entries)
    assert_includes status.fetch(:findings).map { |finding| finding.fetch(:code) }, 'partial_failure'
    assert_includes status.fetch(:findings).map { |finding| finding.fetch(:code) }, 'resume_blocked'
  end

  def test_evaluator_rejects_tampered_static_verification_requirements
    journal = SloRulesEngine::ProviderState::JournalBuilder.new.build(prometheus_plan).to_h
    journal[:entries][0][:verification][:requirements] = ['trust_without_verification']

    status = SloRulesEngine::ProviderState::JournalEvaluator.new.evaluate(journal)

    assert_equal false, status.fetch(:valid)
    assert_equal 'blocked', status.fetch(:status)
    assert_equal 'invalid_operation_journal', status.fetch(:findings).fetch(0).fetch(:code)
    assert_equal 'journal_id', status.fetch(:findings).fetch(0).fetch(:path)
  end

  private

  def datadog_plan
    desired = SloRulesEngine::ProviderState::DesiredState.new(
      provider: 'datadog',
      service: 'checkout-api',
      source: 'provider_manifest',
      resources: {
        slos: [{ name: 'checkout availability', type: 'metric' }],
        dashboards: [{ title: 'checkout decision dashboard' }]
      }
    )
    observed = SloRulesEngine::ProviderState::ObservedState.new(
      provider: 'datadog',
      service: 'checkout-api',
      source: 'backend_api',
      resources: {
        slos: {
          'checkout availability' => {
            id: 'slo-123',
            type: 'time_slice'
          }
        }
      }
    )
    SloRulesEngine::ProviderState::Plan.new(
      provider: 'datadog',
      service: 'checkout-api',
      mode: 'dry_run',
      desired_state: desired,
      observed_state: observed,
      changes: [
        SloRulesEngine::ProviderState::Change.new(
          action: 'recreate',
          target: 'datadog.slo',
          name: 'checkout availability',
          source: 'artifacts.slos[0]',
          desired: { type: 'metric' },
          observed: { type: 'time_slice' },
          changed_paths: ['type'],
          provider_resource_id: 'slo-123',
          match_identity: { strategy: 'source_ref', confidence: 'high' },
          risk: { level: 'high', reasons: ['resource_replacement'] }
        ),
        SloRulesEngine::ProviderState::Change.new(
          action: 'update',
          target: 'datadog.monitor',
          name: 'checkout availability page alert',
          source: 'artifacts.monitors[0]',
          desired: { query: 'burn_rate > 14.4' },
          observed: { query: 'burn_rate > 6' },
          changed_paths: ['query'],
          provider_resource_id: 'monitor-789',
          match_identity: { strategy: 'source_ref', confidence: 'high' },
          risk: { level: 'medium', reasons: ['alert_behavior_changes'] }
        ),
        SloRulesEngine::ProviderState::Change.new(
          action: 'noop',
          target: 'datadog.dashboard',
          name: 'checkout decision dashboard',
          source: 'artifacts.dashboards[0]',
          desired: { title: 'checkout decision dashboard' },
          observed: { title: 'checkout decision dashboard' },
          changed_paths: [],
          provider_resource_id: 'dashboard-456',
          match_identity: { strategy: 'source_ref', confidence: 'high' }
        )
      ],
      findings: [],
      summary: {
        total_operations: 3,
        actionable_operations: 2,
        destructive_operations: 1
      }
    )
  end

  def prometheus_plan
    desired = SloRulesEngine::ProviderState::DesiredState.new(
      provider: 'prometheus_stack',
      service: 'checkout-api',
      source: 'provider_manifest',
      resources: {
        native_resources: {
          prometheus_rule: {
            apiVersion: 'monitoring.coreos.com/v1',
            kind: 'PrometheusRule'
          }
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
    SloRulesEngine::ProviderState::Plan.new(
      provider: 'prometheus_stack',
      service: 'checkout-api',
      mode: 'dry_run',
      desired_state: desired,
      observed_state: observed,
      changes: [
        SloRulesEngine::ProviderState::Change.new(
          action: 'write',
          target: 'prometheus_rule_file',
          name: 'checkout-api.rules.yaml',
          source: 'artifacts.native_resources.prometheus_rule',
          desired: { path: '/managed/checkout-api.rules.yaml' },
          changed_paths: ['content']
        )
      ],
      findings: [],
      summary: {
        total_operations: 1,
        actionable_operations: 1,
        destructive_operations: 0
      }
    )
  end
end
