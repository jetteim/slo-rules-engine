# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require_relative '../scripts/support/structure_inventory'

class ArchitectureFitnessTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  POLICY_PATH = File.join(ROOT, 'config/architecture_dependencies.json')
  CONTRACTS_PATH = File.join(ROOT, 'config/architecture_contracts.json')

  def setup
    @inventory = StructureInventory.new(
      root: ROOT,
      policy_path: POLICY_PATH,
      contracts_path: CONTRACTS_PATH
    )
  end

  def test_boundary_map_assigns_every_production_file_once
    coverage = @inventory.boundary_coverage

    assert_empty coverage.fetch(:unassigned)
    assert_empty coverage.fetch(:multiply_assigned)
    assert_equal @inventory.production_paths.length,
                 coverage.fetch(:boundaries).sum { |boundary| boundary.fetch(:file_count) }
  end

  def test_dependency_debt_is_exact_and_no_new_forbidden_edges_exist
    evaluation = @inventory.dependency_evaluation

    assert evaluation.fetch(:valid), JSON.pretty_generate(evaluation)
    assert_operator evaluation.fetch(:reference_count), :>, 0
    assert evaluation.fetch(:rules).any? { |rule| rule.fetch(:allowed_references).empty? },
           'expected at least one zero-debt boundary rule'
  end

  def test_new_forbidden_dependency_is_reported_with_exact_evidence
    Dir.mktmpdir('architecture-fitness') do |temporary_root|
      source_path = File.join(temporary_root, 'lib/example.rb')
      policy_path = File.join(temporary_root, 'architecture.json')
      FileUtils.mkdir_p(File.dirname(source_path))
      File.write(source_path, "SloRulesEngine::ReleaseBundle::Fingerprint.content(value)\n")
      File.write(
        policy_path,
        JSON.generate(
          boundaries: [],
          rules: [
            {
              id: 'example_to_release',
              intent: 'example must not depend on release',
              source_paths: ['lib/**/*.rb'],
              forbidden_constant_pattern: '(?:SloRulesEngine::)?ReleaseBundle::[A-Z][A-Za-z0-9]*',
              allowed_references: []
            }
          ]
        )
      )
      inventory = StructureInventory.new(
        root: temporary_root,
        policy_path: policy_path,
        contracts_path: File.join(temporary_root, 'unused-contracts.json')
      )

      evaluation = inventory.dependency_evaluation

      refute evaluation.fetch(:valid)
      assert_equal 1, evaluation.fetch(:reference_count)
      assert_equal 'lib/example.rb', evaluation.dig(:rules, 0, :unexpected_references, 0, :path)
      assert_equal 'SloRulesEngine::ReleaseBundle::Fingerprint',
                   evaluation.dig(:rules, 0, :unexpected_references, 0, :constant)
    end
  end

  def test_command_schema_and_use_case_contract_snapshots_match
    evaluation = @inventory.contract_evaluation

    assert evaluation.fetch(:valid), JSON.pretty_generate(evaluation)
    assert_equal 40, evaluation.dig(:actual, :command_ids).length
    assert_equal 21, evaluation.dig(:actual, :schema_ids).length
    assert_equal 19, evaluation.dig(:actual, :use_cases).length
  end

  def test_structure_report_is_deterministic_and_complete
    first = @inventory.report
    second = @inventory.report

    assert_equal JSON.generate(first), JSON.generate(second)
    assert_equal 'structure-report/v1', first.fetch(:schema_version)
    assert_equal 100, first.dig(:production, :file_count)
    assert_equal 64, first.dig(:composition, :root_require_count)
    assert_equal 11, first.dig(:commands, :module_count)
    assert_equal 120, first.dig(:schema_contracts, :command_ref_count)
    assert first.dig(:boundaries, :valid)
    assert first.dig(:dependency_debt, :valid)
    assert first.dig(:contracts, :valid)
  end
end
