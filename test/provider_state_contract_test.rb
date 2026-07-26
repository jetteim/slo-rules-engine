# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/slo_rules_engine'

class ProviderStateContractTest < Minitest::Test
  def test_desired_and_observed_snapshots_are_immutable_and_content_addressed
    resources = {
      slos: [
        {
          name: 'checkout-api availability',
          payload: { type: 'metric' }
        }
      ]
    }
    desired = SloRulesEngine::ProviderState::DesiredState.new(
      provider: 'datadog',
      service: 'checkout-api',
      source: 'provider_manifest',
      resources: resources
    )
    repeated = SloRulesEngine::ProviderState::DesiredState.new(
      provider: 'datadog',
      service: 'checkout-api',
      source: 'provider_manifest',
      resources: resources
    )
    observed = SloRulesEngine::ProviderState::ObservedState.new(
      provider: 'datadog',
      service: 'checkout-api',
      source: 'backend_api',
      resources: {
        slos: {
          'checkout-api availability' => {
            id: 'slo-123',
            payload: { type: 'metric' }
          }
        }
      }
    )

    resources.fetch(:slos).fetch(0).fetch(:payload)[:type] = 'changed-outside-contract'

    assert_equal 'slo-rules-engine/provider-state/v1', desired.to_h.fetch(:schema_version)
    assert_equal 'ProviderDesiredState', desired.to_h.fetch(:kind)
    assert_equal desired.fingerprint, repeated.fingerprint
    assert_match(/\A[0-9a-f]{64}\z/, observed.fingerprint)
    assert_equal 'metric', desired.resources.fetch(:slos).fetch(0).fetch(:payload).fetch(:type)
    assert_raises(FrozenError) do
      desired.resources.fetch(:slos) << { name: 'mutated' }
    end
  end

  def test_change_preserves_provider_payload_identity_and_risk
    operation = SloRulesEngine::ApplyOperation.new(
      action: 'recreate',
      target: 'datadog.monitor',
      name: 'checkout burn monitor',
      source: 'artifacts.monitors[0]',
      payload: { query: 'burn_rate(...) > 14.4' },
      actual: { query: 'burn_rate(...) > 6' },
      changes: ['query'],
      backend_id: 456,
      match_identity: { strategy: 'source_ref', confidence: 'high' },
      risk: { level: 'high', reasons: ['alert_coverage_may_drop'] }
    )

    change = SloRulesEngine::ProviderState::Change.from_apply_operation(operation)
    payload = change.to_h

    assert_equal 'ProviderStateChange', payload.fetch(:kind)
    assert_equal 'recreate', payload.fetch(:action)
    assert_equal({ query: 'burn_rate(...) > 14.4' }, payload.fetch(:desired))
    assert_equal({ query: 'burn_rate(...) > 6' }, payload.fetch(:observed))
    assert_equal ['query'], payload.fetch(:changed_paths)
    assert_equal 456, payload.fetch(:provider_resource_id)
    assert_equal({ strategy: 'source_ref', confidence: 'high' }, payload.fetch(:match_identity))
    assert_equal 'high', payload.fetch(:risk).fetch(:level)
  end

  def test_finding_preserves_provider_specific_evidence
    finding = SloRulesEngine::ProviderState::Finding.from_hash(
      {
        code: 'weak_identity_match',
        message: 'resource matched without managed source identity',
        target: 'datadog.slo',
        source: 'backend_state.slos[0]',
        strategy: 'name',
        confidence: 'medium'
      },
      provider: 'datadog'
    )

    assert_equal(
      {
        schema_version: 'slo-rules-engine/provider-state/v1',
        kind: 'ProviderStateFinding',
        provider: 'datadog',
        code: 'weak_identity_match',
        severity: 'finding',
        message: 'resource matched without managed source identity',
        target: 'datadog.slo',
        source: 'backend_state.slos[0]',
        evidence: {
          strategy: 'name',
          confidence: 'medium'
        }
      },
      finding.to_h
    )
  end

  def test_plan_and_result_share_versioned_state_contracts
    desired = SloRulesEngine::ProviderState::DesiredState.new(
      provider: 'prometheus_stack',
      service: 'checkout-api',
      source: 'provider_manifest',
      resources: { manifest: { provider: 'prometheus_stack' } }
    )
    observed = SloRulesEngine::ProviderState::ObservedState.new(
      provider: 'prometheus_stack',
      service: 'checkout-api',
      source: 'manifest_bundle',
      resources: { files: [] }
    )
    change = SloRulesEngine::ProviderState::Change.new(
      action: 'write',
      target: 'manifest_file',
      name: 'checkout manifest',
      source: 'manifest',
      desired: { path: '/tmp/managed/manifest.json' },
      observed: nil,
      changed_paths: ['manifest']
    )
    finding = SloRulesEngine::ProviderState::Finding.new(
      provider: 'prometheus_stack',
      code: 'review_required',
      message: 'review before apply'
    )
    plan = SloRulesEngine::ProviderState::Plan.new(
      provider: 'prometheus_stack',
      service: 'checkout-api',
      mode: 'dry_run',
      desired_state: desired,
      observed_state: observed,
      changes: [change],
      findings: [finding],
      summary: { total_operations: 1 }
    )
    repeated_plan = SloRulesEngine::ProviderState::Plan.new(
      provider: 'prometheus_stack',
      service: 'checkout-api',
      mode: 'dry_run',
      desired_state: desired,
      observed_state: observed,
      changes: [change],
      findings: [finding],
      summary: { total_operations: 1 }
    )
    result = SloRulesEngine::ProviderState::Result.new(
      provider: 'prometheus_stack',
      service: 'checkout-api',
      mode: 'live',
      status: 'succeeded',
      desired_state_fingerprint: desired.fingerprint,
      observed_state_fingerprint: observed.fingerprint,
      plan_fingerprint: plan.fingerprint,
      operation_results: [
        {
          target: 'manifest_file',
          action: 'write',
          status: 'succeeded'
        }
      ],
      findings: [],
      verification: {
        status: 'pending',
        reason: 'post-apply verification is not implemented yet'
      }
    )

    assert_equal 'ProviderStatePlan', plan.to_h.fetch(:kind)
    assert_match(/\A[0-9a-f]{64}\z/, plan.to_h.fetch(:fingerprint))
    assert_equal plan.fingerprint, repeated_plan.fingerprint
    assert_equal desired.fingerprint, plan.to_h.dig(:desired_state, :fingerprint)
    assert_equal observed.fingerprint, plan.to_h.dig(:observed_state, :fingerprint)
    assert_equal 'ProviderStateChange', plan.to_h.fetch(:changes).fetch(0).fetch(:kind)
    assert_equal 'ProviderStateFinding', plan.to_h.fetch(:findings).fetch(0).fetch(:kind)
    assert_equal 'ProviderStateResult', result.to_h.fetch(:kind)
    assert_equal 'succeeded', result.to_h.fetch(:status)
    assert_equal plan.fingerprint, result.to_h.fetch(:plan_fingerprint)
    assert_equal 'pending', result.to_h.dig(:verification, :status)
  end

  def test_contracts_reject_missing_stable_identity
    error = assert_raises(SloRulesEngine::ProviderState::ContractError) do
      SloRulesEngine::ProviderState::DesiredState.new(
        provider: 'datadog',
        service: '',
        source: 'provider_manifest',
        resources: {}
      )
    end

    assert_equal 'service', error.path
  end
end
