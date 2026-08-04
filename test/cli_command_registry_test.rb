# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/slo_rules_engine/cli'

class CliCommandRegistryTest < Minitest::Test
  EXPECTED_COMMAND_IDS = %w[
    validate
    validate-handoff
    generate
    manifest-review
    apply
    diff
    import
    prune
    status
    bundle.create
    bundle.plan
    bundle.apply
    bundle.verify
    bundle.status
    journal.create
    journal.status
    plan.approve
    plan.status
    plan.apply
    plan.resume
    lookup-telemetry
    discover-telemetry
    providers.list
    integrations.list
    generate-routes
    candidates
    draft-definition
    draft-from-handoff
    onboarding-summary
    onboarding-artifact-index
    review-handoff
    recommend-calculation-basis
    reality-check
    migration-report
    model-report
  ].freeze

  def setup
    @registry = SloRulesEngine::CLI::CommandRegistry.default
  end

  def test_registry_is_the_complete_versioned_current_command_inventory
    assert_equal 'slo-rules-engine/cli-command-registry/v1', @registry.schema_version
    assert_equal EXPECTED_COMMAND_IDS, @registry.definitions.map(&:id)
    assert_equal EXPECTED_COMMAND_IDS.length, @registry.human_paths.uniq.length

    @registry.definitions.each do |definition|
      assert_equal 1, definition.version, definition.id
      assert_match(/\A[a-z][a-z0-9.-]*\z/, definition.id)
      refute_empty definition.human_path
      assert_match(/\Abin\/rules-ctl /, definition.human_usage)
      assert_kind_of Symbol, definition.adapter
      assert_kind_of Symbol, definition.handler
      assert_equal definition.id, definition.agent.fetch(:command_id)
      assert_equal 'planned', definition.agent.fetch(:status)
      request_example = definition.agent.fetch(:request_example)
      assert_equal 'slo-rules-engine/agent-command-request/v1', request_example.fetch(:schema_version)
      assert_equal definition.id, request_example.fetch(:command_id)
      assert_equal definition.version, request_example.fetch(:command_version)
      assert_kind_of Hash, request_example.fetch(:arguments)
      assert_equal 'planned', definition.mcp.fetch(:status)
      assert_includes [true, false], definition.mcp.fetch(:eligible)
      assert_equal %i[request result error], definition.schemas.keys
      definition.schemas.each_value do |schema|
        assert_match(%r{\Aslo-rules-engine/cli-command-contract/.+/v1\z}, schema.fetch(:ref))
        assert_includes %w[characterized planned], schema.fetch(:status)
      end
      assert_includes SloRulesEngine::CLI::CommandDefinition::SIDE_EFFECT_CLASSES,
                      definition.side_effect
      assert_equal %i[local_reads local_writes provider_reads provider_writes credentials],
                   definition.io.keys
      definition.io.each_value { |values| assert_kind_of Array, values }
      refute_empty definition.safety_gates
      assert_equal %i[stdout persisted_artifacts field_masks streaming], definition.output.keys
      assert definition.frozen?
      assert definition.human_path.frozen?
      assert definition.agent.frozen?
      assert definition.schemas.frozen?
      assert definition.io.frozen?
      assert definition.safety_gates.frozen?
      assert definition.output.frozen?
      assert definition.mcp.frozen?
    end
  end

  def test_human_paths_resolve_to_existing_handlers_without_consuming_subcommands
    assert_equal :validate, @registry.handler_for_human_root('validate')
    assert_equal :bundle, @registry.handler_for_human_root('bundle')
    assert_equal :journal, @registry.handler_for_human_root('journal')
    assert_equal :plan, @registry.handler_for_human_root('plan')
    assert_equal :providers, @registry.handler_for_human_root('providers')
    assert_equal :integrations, @registry.handler_for_human_root('integrations')
    assert_nil @registry.handler_for_human_root('unknown')
    assert_equal :bundle_create, @registry.fetch('bundle.create').handler
    assert_equal :bundle, @registry.fetch('bundle.create').adapter
    assert_equal :providers_list, @registry.fetch('providers.list').handler
    assert_equal :providers, @registry.fetch('providers.list').adapter

    @registry.definitions.each do |definition|
      assert_respond_to RulesCtl, definition.adapter, definition.id
      assert_respond_to RulesCtl, definition.handler, definition.id
      assert_same definition, @registry.fetch_human(definition.human_path)
    end

    dispatcher = File.read(File.join(__dir__, '..', 'lib', 'slo_rules_engine', 'cli.rb'))
    assert_includes dispatcher, 'command_registry.handler_for_human_root(command)'
    refute_includes dispatcher, 'case command'
  end

  def test_registry_records_mutation_and_zero_io_boundaries_explicitly
    assert_equal 'provider_mutation', @registry.fetch('apply').side_effect
    assert_equal %w[provider_state managed_files], @registry.fetch('apply').io.fetch(:provider_writes)
    assert_equal @registry.fetch('apply').io.fetch(:local_writes),
                 @registry.fetch('apply').output.fetch(:persisted_artifacts)
    assert_includes @registry.fetch('apply').safety_gates, 'reviewed_manifest'
    assert_includes @registry.fetch('apply').safety_gates, 'explicit_confirmation'
    assert_includes @registry.fetch('apply').safety_gates, 'durable_journal'

    assert_equal 'provider_mutation', @registry.fetch('prune').side_effect
    assert_includes @registry.fetch('prune').safety_gates, 'managed_ownership'
    assert_equal 'local_write', @registry.fetch('bundle.apply').side_effect
    assert_includes @registry.fetch('bundle.apply').safety_gates, 'approved_exact_plan'
    assert_includes @registry.fetch('bundle.apply').output.fetch(:persisted_artifacts), 'applied_bundle'

    providers = @registry.fetch('providers.list')
    assert_equal 'none', providers.side_effect
    assert providers.io.values.all?(&:empty?)
    assert_empty providers.output.fetch(:persisted_artifacts)
  end

  def test_separate_catalog_pairs_human_commands_with_agent_json_requests
    catalog = SloRulesEngine::CLI::CommandCatalog.to_h

    assert_equal 'slo-rules-engine/cli-command-catalog/v1', catalog.fetch(:schema_version)
    assert_equal EXPECTED_COMMAND_IDS, catalog.fetch(:commands).map { |entry| entry.fetch(:id) }
    catalog.fetch(:commands).each do |entry|
      assert_equal %i[id human_cli agent_cli_json], entry.keys
      assert_match(/\Abin\/rules-ctl /, entry.fetch(:human_cli))
      assert_equal entry.fetch(:id), entry.fetch(:agent_cli_json).fetch(:command_id)
      assert_kind_of Hash, entry.fetch(:agent_cli_json).fetch(:arguments)
    end

    validate = catalog.fetch(:commands).find { |entry| entry.fetch(:id) == 'validate' }
    assert_equal 'bin/rules-ctl validate ./service.rb', validate.fetch(:human_cli)
    assert_equal ['./service.rb'], validate.fetch(:agent_cli_json).fetch(:arguments).fetch(:definition_files)

    apply = catalog.fetch(:commands).find { |entry| entry.fetch(:id) == 'apply' }
    assert_equal 'plan', apply.fetch(:agent_cli_json).fetch(:arguments).fetch(:mode)
    assert_equal './manifest.json', apply.fetch(:agent_cli_json).fetch(:arguments).fetch(:manifest_file)
  end

  def test_invalid_or_duplicate_metadata_fails_closed
    error = assert_raises(SloRulesEngine::CLI::CommandRegistry::InvalidRegistry) do
      SloRulesEngine::CLI::CommandRegistry.new([])
    end
    assert_includes error.message, 'at least one command'

    definition = @registry.fetch('validate')
    error = assert_raises(SloRulesEngine::CLI::CommandRegistry::InvalidRegistry) do
      SloRulesEngine::CLI::CommandRegistry.new([definition, definition])
    end
    assert_includes error.message, 'duplicate command id'

    error = assert_raises(SloRulesEngine::CLI::CommandDefinition::InvalidDefinition) do
      SloRulesEngine::CLI::CommandDefinition.new(
        id: 'broken',
        version: 1,
        human_path: ['broken'],
        human_usage: 'bin/rules-ctl broken',
        adapter: :broken,
        handler: :broken,
        agent: {},
        schemas: {},
        side_effect: 'none',
        io: {},
        safety_gates: [],
        output: {},
        mcp: {}
      )
    end
    assert_includes error.message, 'agent'
  end

  def test_registry_serialization_is_deterministic_and_credential_free
    first = @registry.to_h
    second = SloRulesEngine::CLI::CommandRegistry.default.to_h

    assert_equal first, second
    assert_equal @registry.schema_version, first.fetch(:schema_version)
    assert_equal EXPECTED_COMMAND_IDS, first.fetch(:commands).map { |command| command.fetch(:id) }
    serialized = JSON.generate(first)
    refute_match(/api[_-]?key|app[_-]?key|authorization/i, serialized)
  end
end
