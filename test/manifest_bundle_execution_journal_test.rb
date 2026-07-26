# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/slo_rules_engine'

class ManifestBundleExecutionJournalTest < Minitest::Test
  def test_prometheus_apply_persists_successful_operation_outcomes_and_result
    Dir.mktmpdir do |dir|
      managed_dir = File.join(dir, 'managed')
      journal_dir = File.join(dir, 'journals')
      plan = SloRulesEngine::Appliers::ManifestBundle.new(
        output_dir: managed_dir,
        journal_dir: journal_dir,
        clock: fixed_clock
      ).apply(valid_prometheus_manifest)
      execution = plan.to_h.fetch(:execution)
      journal_path = execution.dig(:operation_journal, :path)
      journal = JSON.parse(File.read(journal_path), symbolize_names: true)
      result = execution.fetch(:result)

      assert_equal 'succeeded', journal.fetch(:status)
      assert_equal %w[succeeded succeeded succeeded succeeded],
                   journal.fetch(:entries).map { |entry| entry.fetch(:status) }
      assert_equal 'ProviderStateResult', result.fetch(:kind)
      assert_equal 'succeeded', result.fetch(:status)
      assert_equal journal.dig(:plan, :fingerprint), result.fetch(:plan_fingerprint)
      assert_equal journal.fetch(:journal_id), execution.dig(:operation_journal, :journal_id)
      assert_equal journal_path, execution.dig(:operation_journal, :path)
      result.fetch(:operation_results).each do |operation_result|
        assert File.exist?(operation_result.fetch(:provider_resource_id))
      end
    end
  end

  def test_prometheus_apply_records_partial_failure_and_skips_remaining_files
    Dir.mktmpdir do |dir|
      managed_dir = File.join(dir, 'managed')
      journal_dir = File.join(dir, 'journals')
      generated_path = File.join(managed_dir, 'checkout-api', 'prometheus_stack', 'generated')
      FileUtils.mkdir_p(File.dirname(generated_path))
      File.write(generated_path, 'blocks generated directory creation')

      plan = SloRulesEngine::Appliers::ManifestBundle.new(
        output_dir: managed_dir,
        journal_dir: journal_dir,
        clock: fixed_clock
      ).apply(valid_prometheus_manifest)
      execution = plan.to_h.fetch(:execution)
      journal = JSON.parse(
        File.read(execution.dig(:operation_journal, :path)),
        symbolize_names: true
      )

      assert_equal 'partial', execution.dig(:result, :status)
      assert_equal %w[succeeded failed skipped skipped],
                   journal.fetch(:entries).map { |entry| entry.fetch(:status) }
      assert_equal 'file_operation_failed',
                   journal.dig(:entries, 1, :attempts, 0, :error, :code)
      assert_equal 'prior_operation_failed', journal.dig(:entries, 2, :skip, :reason)
      assert File.exist?(File.join(managed_dir, 'checkout-api', 'prometheus_stack', 'manifest.json'))
      refute File.exist?(File.join(generated_path, 'prometheus-rules.yaml'))
      assert_includes execution.dig(:result, :findings).map { |finding| finding.fetch(:code) },
                      'partial_failure'
    end
  end

  def test_sloth_apply_records_external_handoff_as_intentionally_skipped
    Dir.mktmpdir do |dir|
      plan = SloRulesEngine::Appliers::ManifestBundle.new(
        output_dir: File.join(dir, 'managed'),
        journal_dir: File.join(dir, 'journals'),
        clock: fixed_clock
      ).apply(valid_sloth_manifest)
      execution = plan.to_h.fetch(:execution)
      journal = JSON.parse(
        File.read(execution.dig(:operation_journal, :path)),
        symbolize_names: true
      )
      handoff = journal.fetch(:entries).fetch(2)

      assert_equal %w[succeeded succeeded skipped],
                   journal.fetch(:entries).map { |entry| entry.fetch(:status) }
      assert_equal 'external_handoff_required', handoff.dig(:skip, :reason)
      assert_equal 'succeeded', execution.dig(:result, :status)
      assert_includes execution.dig(:result, :findings).map { |finding| finding.fetch(:code) },
                      'non_resumable_operation'
    end
  end

  def test_prometheus_prune_persists_delete_outcomes
    Dir.mktmpdir do |dir|
      managed_dir = File.join(dir, 'managed')
      applier = SloRulesEngine::Appliers::ManifestBundle.new(output_dir: managed_dir)
      apply_plan = applier.apply(valid_prometheus_manifest)
      paths = apply_plan.operations.map { |operation| operation.payload.fetch(:path) }

      prune_plan = SloRulesEngine::Appliers::ManifestBundle.new(
        output_dir: managed_dir,
        journal_dir: File.join(dir, 'journals'),
        clock: fixed_clock
      ).prune(valid_prometheus_manifest, mode: 'live')
      execution = prune_plan.to_h.fetch(:execution)

      assert_equal 'succeeded', execution.dig(:result, :status)
      assert_equal %w[succeeded succeeded succeeded succeeded],
                   execution.dig(:result, :operation_results).map { |result| result.fetch(:status) }
      paths.each { |path| refute File.exist?(path) }
    end
  end

  def test_repeated_converged_apply_reuses_the_identical_noop_journal
    Dir.mktmpdir do |dir|
      applier = SloRulesEngine::Appliers::ManifestBundle.new(
        output_dir: File.join(dir, 'managed'),
        journal_dir: File.join(dir, 'journals'),
        clock: fixed_clock
      )
      manifest = valid_prometheus_manifest
      applier.apply(manifest)

      first_noop = applier.apply(manifest).to_h.fetch(:execution)
      repeated_noop = applier.apply(manifest).to_h.fetch(:execution)

      assert_equal 'noop', first_noop.dig(:result, :status)
      assert_equal first_noop.dig(:operation_journal, :journal_id),
                   repeated_noop.dig(:operation_journal, :journal_id)
      assert_equal first_noop.dig(:operation_journal, :path),
                   repeated_noop.dig(:operation_journal, :path)
    end
  end

  private

  def fixed_clock
    tick = 0
    lambda do
      value = Time.utc(2026, 7, 26, 12, 0, tick)
      tick += 1
      value
    end
  end

  def valid_prometheus_manifest
    SloRulesEngine.clear_definitions
    load File.expand_path('../examples/services/checkout.rb', __dir__)
    definition = SloRulesEngine.definitions.fetch(0)
    SloRulesEngine.default_provider_registry.fetch('prometheus_stack').generate(definition).to_h.merge(
      service: definition.service
    )
  end

  def valid_sloth_manifest
    SloRulesEngine.clear_definitions
    load File.expand_path('../examples/services/checkout.rb', __dir__)
    definition = SloRulesEngine.definitions.fetch(0)
    SloRulesEngine.default_provider_registry.fetch('sloth').generate(definition).to_h.merge(
      service: definition.service
    )
  end
end
