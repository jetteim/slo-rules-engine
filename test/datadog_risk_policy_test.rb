# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/slo_rules_engine'
require_relative '../lib/slo_rules_engine/datadog/risk_policy'

class DatadogRiskPolicyTest < Minitest::Test
  def test_flags_provider_specific_recreate_and_prune_risks
    policy = SloRulesEngine::Datadog::RiskPolicy.new

    recreate = policy.operation_risk(action: 'recreate', target: 'datadog.monitor')
    prune = policy.operation_risk(action: 'delete', target: 'datadog.slo')

    assert_equal 'high', recreate.fetch(:level)
    assert_equal ['recreate_deletes_existing_monitor', 'alert_coverage_may_drop'], recreate.fetch(:reasons)
    assert_equal 'high', prune.fetch(:level)
    assert_equal ['prune_force_deletes_managed_slo', 'slo_coverage_removed'], prune.fetch(:reasons)
  end

  def test_merges_weak_identity_and_operation_risks
    policy = SloRulesEngine::Datadog::RiskPolicy.new

    risk = policy.merge(
      policy.operation_risk(action: 'delete', target: 'datadog.dashboard'),
      policy.weak_identity_risk(strategy: 'name', confidence: 'medium')
    )

    assert_equal 'medium', risk.fetch(:level)
    assert_equal ['prune_deletes_managed_dashboard', 'matched_without_source_ref'], risk.fetch(:reasons)
  end

  def test_ignores_high_confidence_identity
    policy = SloRulesEngine::Datadog::RiskPolicy.new

    assert_nil policy.weak_identity_risk(strategy: 'source_ref', confidence: 'high')
  end
end
