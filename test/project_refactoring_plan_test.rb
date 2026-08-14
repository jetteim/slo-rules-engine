# frozen_string_literal: true

require 'minitest/autorun'

class ProjectRefactoringPlanTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  PLAN = File.join(ROOT, 'docs', 'housekeeping', 'project-structure-refactoring-plan.md')

  def test_plan_is_evidence_based_and_covers_every_engineering_use_case
    plan = File.read(PLAN)

    assert_includes plan, 'Baseline commit: `6dc0ffb`'
    assert_includes plan, '21,467'
    assert_includes plan, '16,092'
    assert_includes plan, '63 direct requires'
    (1..19).each { |number| assert_match(/UC-#{format('%02d', number)}\b/, plan) }
  end

  def test_plan_accounts_for_current_hotspots_and_dependency_debt
    plan = File.read(PLAN)

    %w[
      sloth/downstream_evidence.rb
      provider_state/journal_execution.rb
      release_bundle/verifier.rb
      sloth/mcp/comparison.rb
      appliers/manifest_bundle.rb
      cli/command_registry.rb
      cli.rb
    ].each { |path| assert_includes plan, path }
    assert_includes plan, 'ReleaseBundle -> LiveStatus'
    assert_includes plan, 'ProviderState -> ReleaseBundle'
    assert_includes plan, 'CredentialScanner'
    assert_includes plan, 'Fingerprint'
  end

  def test_plan_is_sliced_reversible_and_preserves_contracts
    plan = File.read(PLAN)

    (0..7).each { |number| assert_includes plan, "STR-#{number}" }
    assert_includes plan, 'one independently revertible checkpoint'
    assert_includes plan, 'Human CLI and Agent CLI'
    assert_includes plan, 'versioned schemas'
    assert_includes plan, 'provider reads and writes'
    assert_includes plan, 'refusal codes'
    assert_includes plan, './scripts/verify.sh'
    assert_includes plan, 'Freeze Zones'
    assert_includes plan, 'Revalidation'
  end
end
