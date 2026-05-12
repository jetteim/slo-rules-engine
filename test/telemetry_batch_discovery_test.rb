# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'tempfile'
require 'tmpdir'
require_relative '../lib/slo_rules_engine'

class TelemetryBatchDiscoveryTest < Minitest::Test
  def test_load_scopes_rejects_entries_without_scope_fields
    Tempfile.create(['scopes', '.json']) do |file|
      file.write(JSON.generate([{ label: 'empty-scope' }]))
      file.flush

      error = assert_raises(ArgumentError) do
        SloRulesEngine::TelemetryBatchDiscovery.load_scopes(file.path, provider: 'datadog')
      end

      assert_includes error.message, 'must define at least one of service, selectors, or host'
    end
  end

  def test_load_scopes_rejects_duplicate_normalized_labels
    Tempfile.create(['scopes', '.json']) do |file|
      file.write(JSON.generate([
        { label: 'checkout prod', service: 'checkout-api' },
        { label: 'checkout-prod', service: 'checkout-worker' }
      ]))
      file.flush

      error = assert_raises(ArgumentError) do
        SloRulesEngine::TelemetryBatchDiscovery.load_scopes(file.path, provider: 'prometheus_stack')
      end

      assert_includes error.message, 'duplicate normalized label'
    end
  end

  def test_runner_writes_one_result_per_scope_and_index
    adapter = FakeDiscoveryAdapter.new(
      {
        ['checkout-api', { 'env' => 'prod' }, nil] => SloRulesEngine::TelemetryLookup::Result.new(
          provider: 'datadog',
          signals: [SloRulesEngine::TelemetryLookup.discovered_signal(metric: 'http.server.request.duration', source: 'datadog')],
          findings: []
        ),
        [nil, { 'team' => 'payments' }, nil] => SloRulesEngine::TelemetryLookup::Result.new(
          provider: 'datadog',
          signals: [SloRulesEngine::TelemetryLookup.discovered_signal(metric: 'payments.checkout.completed', source: 'datadog')],
          findings: []
        )
      }
    )
    scopes = [
      SloRulesEngine::TelemetryBatchDiscovery::Scope.new(label: 'checkout-prod', service: 'checkout-api', selectors: { 'env' => 'prod' }),
      SloRulesEngine::TelemetryBatchDiscovery::Scope.new(label: 'payments-prod', selectors: { 'team' => 'payments' })
    ]

    Dir.mktmpdir do |dir|
      result = SloRulesEngine::TelemetryBatchDiscovery::Runner.new(
        provider: 'datadog',
        adapter: adapter,
        output_dir: dir,
        time_fn: -> { '2026-05-12T10:00:00Z' }
      ).run(scopes)

      assert_equal 2, result.fetch(:total_scopes)
      assert_equal 2, result.fetch(:successful_scopes)
      assert_equal 0, result.fetch(:failed_scopes)
      assert File.exist?(File.join(dir, 'checkout-prod.json'))
      assert File.exist?(File.join(dir, 'payments-prod.json'))
      assert File.exist?(File.join(dir, 'index.json'))

      checkout_payload = JSON.parse(File.read(File.join(dir, 'checkout-prod.json')))
      assert_equal 'datadog', checkout_payload.fetch('provider')
      assert_equal 'checkout-prod', checkout_payload.fetch('scope').fetch('label')
      assert_equal 1, checkout_payload.fetch('signals').length
    end
  end

  class FakeDiscoveryAdapter
    def initialize(results)
      @results = results
    end

    def discover(service: nil, selectors: {}, host: nil)
      @results.fetch([service, selectors, host])
    end
  end
end
