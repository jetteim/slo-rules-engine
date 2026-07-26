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
      assert_equal 'succeeded', result.dig(:verification, :status)
      assert_equal 'succeeded', result.dig(:verification, :engine_owned_status)
      assert_equal 'not_required', result.dig(:verification, :external_status)
      assert_equal 4, result.dig(:verification, :summary, :succeeded_resources)
      journal.fetch(:entries).each do |entry|
        verification = entry.fetch(:verification)
        assert_equal 'succeeded', verification.fetch(:status)
        assert_match(/\A2026-07-26T12:00:\d{2}\.000000Z\z/, verification.fetch(:checked_at))
        assert_equal verification.dig(:expected, :fingerprint),
                     verification.dig(:actual, :fingerprint)
      end
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
      assert_equal 'failed', execution.dig(:result, :verification, :status)
      assert_operator execution.dig(:result, :verification, :summary, :failed_resources), :>=, 1
      assert_includes execution.dig(:result, :findings).map { |finding| finding.fetch(:code) },
                      'post_apply_verification_failed'
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
      assert_equal 'pending', execution.dig(:result, :verification, :status)
      assert_equal 'succeeded', execution.dig(:result, :verification, :engine_owned_status)
      assert_equal 'pending', execution.dig(:result, :verification, :external_status)
      assert_equal 'pending', handoff.dig(:verification, :status)
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
      assert_equal 'succeeded', execution.dig(:result, :verification, :status)
      assert_equal %w[succeeded succeeded succeeded succeeded],
                   execution.dig(:result, :operation_results).map { |result| result.fetch(:status) }
      execution.dig(:result, :verification, :resources).each do |verification|
        assert_equal false, verification.dig(:expected, :present)
        assert_equal false, verification.dig(:actual, :present)
      end
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
      assert_equal 'not_required', first_noop.dig(:result, :verification, :status)
    end
  end

  def test_post_write_content_drift_fails_verification_and_the_provider_result
    Dir.mktmpdir do |dir|
      verifier = TamperingVerifier.new(
        SloRulesEngine::ProviderState::ManagedFileVerifier.new
      )
      plan = SloRulesEngine::Appliers::ManifestBundle.new(
        output_dir: File.join(dir, 'managed'),
        journal_dir: File.join(dir, 'journals'),
        clock: fixed_clock,
        verifier: verifier
      ).apply(valid_prometheus_manifest)
      execution = plan.to_h.fetch(:execution)
      journal = JSON.parse(
        File.read(execution.dig(:operation_journal, :path)),
        symbolize_names: true
      )

      assert_equal 'succeeded', journal.fetch(:status)
      assert_equal 'failed', execution.dig(:result, :status)
      assert_equal 'failed', execution.dig(:result, :verification, :status)
      assert_equal 'managed_file_content_mismatch',
                   journal.dig(:entries, 0, :verification, :findings, 0, :code)
      refute_equal journal.dig(:entries, 0, :verification, :expected, :fingerprint),
                   journal.dig(:entries, 0, :verification, :actual, :fingerprint)
    end
  end

  def test_failed_delete_verification_records_that_the_managed_path_remains
    Dir.mktmpdir do |dir|
      managed_dir = File.join(dir, 'managed')
      manifest = valid_prometheus_manifest
      initial = SloRulesEngine::Appliers::ManifestBundle.new(output_dir: managed_dir).apply(manifest)
      manifest_path = initial.operations.fetch(0).payload.fetch(:path)
      File.delete(manifest_path)
      Dir.mkdir(manifest_path)

      plan = SloRulesEngine::Appliers::ManifestBundle.new(
        output_dir: managed_dir,
        journal_dir: File.join(dir, 'journals'),
        clock: fixed_clock
      ).prune(manifest, mode: 'live')
      execution = plan.to_h.fetch(:execution)
      journal = JSON.parse(
        File.read(execution.dig(:operation_journal, :path)),
        symbolize_names: true
      )

      assert_equal 'failed', execution.dig(:result, :status)
      assert_equal 'failed', execution.dig(:result, :verification, :status)
      assert_equal 'managed_file_present_after_delete',
                   journal.dig(:entries, 0, :verification, :findings, 0, :code)
      assert_equal true, journal.dig(:entries, 0, :verification, :actual, :present)
      assert_includes execution.dig(:result, :findings).map { |finding| finding.fetch(:code) },
                      'post_apply_verification_failed'
    end
  end

  private

  class TamperingVerifier
    def initialize(delegate)
      @delegate = delegate
      @tampered = false
    end

    def verify(entry, checked_at:)
      unless @tampered
        File.write(entry.dig(:desired, :path), JSON.generate(tampered: true))
        @tampered = true
      end
      @delegate.verify(entry, checked_at: checked_at)
    end
  end

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
