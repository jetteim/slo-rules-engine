# frozen_string_literal: true

require 'minitest/autorun'
require 'digest'
require_relative '../lib/slo_rules_engine/cli'

class CommandContractPreservationTest < Minitest::Test
  GOLDEN_PATH = File.join(__dir__, 'fixtures/command-contracts/hk05-baseline.json')

  def test_registry_catalog_and_all_descriptions_preserve_their_wire_contracts
    registry = SloRulesEngine::CLI::CommandRegistry.default
    reader = SloRulesEngine::CLI::AgentIntrospection.new(registry)
    payload = JSON.parse(JSON.generate(
      registry: registry.to_h,
      catalog: SloRulesEngine::CLI::CommandCatalog.to_h,
      agent_catalog: reader.catalog(limit: 100),
      descriptions: registry.definitions.to_h { |definition| [definition.id, reader.describe(definition.id)] }
    ))
    # HK-05 changes only authoring provenance from inferred to explicit.
    # Keep every resolved schema, example, handler, safety field, and order.
    payload.fetch('registry').fetch('commands').each { |entry| entry.delete('request_schema_source') }
    payload.fetch('agent_catalog').fetch('commands').each { |entry| entry.delete('request_schema_source') }
    payload.fetch('descriptions').each_value { |entry| entry.fetch('command').delete('request_schema_source') }
    expected = JSON.parse(File.read(GOLDEN_PATH)).fetch('sha256')
    payload.each do |name, value|
      assert_equal expected.fetch(name), Digest::SHA256.hexdigest(JSON.generate(value)), name
    end
    assert_equal 13, registry.definitions.count { |definition| definition.agent[:application_command] }
  end

  def test_loaded_families_have_one_explicit_owner_for_each_declared_command
    registry = SloRulesEngine::CLI::CommandRegistry.default
    contracts = SloRulesEngine::CLI::CommandContracts
    families = contracts.constants(false).map { |name| contracts.const_get(name, false) }
    definitions = families.flat_map(&:definitions)
    assert_equal definitions.map(&:id).uniq, definitions.map(&:id)
    definitions.each do |definition|
      assert_same definition, registry.fetch(definition.id), definition.id
      assert_equal 'explicit', definition.request_schema_source, definition.id
    end
  end
end
