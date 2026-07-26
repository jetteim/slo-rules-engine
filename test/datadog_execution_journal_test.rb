# frozen_string_literal: true

require 'tmpdir'
require_relative 'support/datadog_apply_test_case'

class DatadogApplyTest < Minitest::Test
  def test_datadog_apply_persists_mutation_ids_and_verified_backend_state
    Dir.mktmpdir do |dir|
      client = FakeDatadogClient.new
      plan = journaled_applier(client, dir).apply(@manifest)
      execution = plan.to_h.fetch(:execution)
      journal = read_journal(execution)
      result = execution.fetch(:result)

      assert_equal 'succeeded', journal.fetch(:status)
      assert_equal %w[succeeded succeeded succeeded succeeded],
                   journal.fetch(:entries).map { |entry| entry.fetch(:status) }
      assert_equal 'succeeded', result.fetch(:status)
      assert_equal 'succeeded', result.dig(:verification, :status)
      assert_equal 4, result.dig(:verification, :summary, :succeeded_resources)
      assert_equal 2, client.existing_state_requests.length
      journal.fetch(:entries).each do |entry|
        attempt_result = entry.dig(:attempts, 0, :result)
        refute_nil attempt_result.fetch(:provider_resource_id)
        assert_match(/\A[0-9a-f]{64}\z/, attempt_result.dig(:response, :fingerprint))
        refute_empty attempt_result.fetch(:requests)
        assert_equal 'succeeded', entry.dig(:verification, :status)
      end
      refute_match(/secret-value|authorization token/i, File.read(execution.dig(:operation_journal, :path)))
    end
  end

  def test_datadog_apply_records_partial_api_failure_without_leaking_backend_message
    Dir.mktmpdir do |dir|
      client = FailingMonitorClient.new
      plan = journaled_applier(client, dir).apply(@manifest)
      execution = plan.to_h.fetch(:execution)
      journal = read_journal(execution)

      assert_equal %w[succeeded failed skipped skipped],
                   journal.fetch(:entries).map { |entry| entry.fetch(:status) }
      assert_equal 'partial', execution.dig(:result, :status)
      assert_equal 'failed', execution.dig(:result, :verification, :status)
      assert_equal 'datadog_api_request_failed',
                   journal.dig(:entries, 1, :attempts, 0, :error, :code)
      assert_equal 'Datadog API request failed',
                   journal.dig(:entries, 1, :attempts, 0, :error, :message)
      persisted = File.read(execution.dig(:operation_journal, :path))
      refute_includes persisted, 'secret-value'
      assert_includes execution.dig(:result, :findings).map { |finding| finding.fetch(:code) },
                      'partial_failure'
      assert_includes execution.dig(:result, :findings).map { |finding| finding.fetch(:code) },
                      'post_apply_verification_failed'
    end
  end

  def test_datadog_apply_fails_result_when_backend_reread_does_not_match
    Dir.mktmpdir do |dir|
      client = FakeDatadogClient.new(skip_mutation_paths: ['/api/v1/dashboard'])
      plan = journaled_applier(client, dir).apply(@manifest)
      execution = plan.to_h.fetch(:execution)
      journal = read_journal(execution)

      assert_equal 'succeeded', journal.fetch(:status)
      assert_equal 'failed', execution.dig(:result, :status)
      assert_equal 'failed', execution.dig(:result, :verification, :status)
      dashboard = journal.fetch(:entries).find { |entry| entry.fetch(:target) == 'datadog.dashboard' }
      assert_equal 'backend_resource_missing_after_apply',
                   dashboard.dig(:verification, :findings, 0, :code)
      assert_includes execution.dig(:result, :findings).map { |finding| finding.fetch(:code) },
                      'post_apply_verification_failed'
    end
  end

  def test_datadog_prune_persists_deleted_ids_and_verifies_absence
    Dir.mktmpdir do |dir|
      client = FakeDatadogClient.new(managed_state: managed_state_with_orphans)
      plan = journaled_applier(client, dir).prune(@manifest, mode: 'live')
      execution = plan.to_h.fetch(:execution)
      journal = read_journal(execution)

      assert_equal 'succeeded', execution.dig(:result, :status)
      assert_equal 'succeeded', execution.dig(:result, :verification, :status)
      assert_equal %w[succeeded succeeded succeeded],
                   journal.fetch(:entries).map { |entry| entry.fetch(:status) }
      assert_equal [999, 'dashboard-orphan', 'slo-orphan'],
                   execution.dig(:result, :operation_results).map { |operation|
                     operation.fetch(:provider_resource_id)
                   }
      journal.fetch(:entries).each do |entry|
        assert_equal false, entry.dig(:verification, :actual, :present)
      end
    end
  end

  def test_datadog_update_and_recreate_record_the_resulting_backend_identity
    Dir.mktmpdir do |dir|
      client = FakeDatadogClient.new
      SloRulesEngine::Appliers::Datadog.new(client: client).apply(@manifest)
      slo = client.state.fetch(:slos).values.fetch(0)
      slo[:payload] = slo.fetch(:payload).merge(description: 'drifted description')
      monitor = client.state.fetch(:monitors).values.find do |resource|
        resource.dig(:payload, :type) == 'slo alert'
      end
      monitor[:payload] = monitor.fetch(:payload).merge(
        query: 'burn_rate("stale-slo-id").over("30d") > 14.4'
      )
      old_monitor_id = monitor.fetch(:id)

      plan = journaled_applier(client, dir).apply(@manifest)
      journal = read_journal(plan.to_h.fetch(:execution))
      slo_entry = journal.fetch(:entries).find { |entry| entry.fetch(:target) == 'datadog.slo' }
      monitor_entry = journal.fetch(:entries).find do |entry|
        entry.fetch(:target) == 'datadog.monitor' && entry.fetch(:action) == 'recreate'
      end

      assert_equal 'update', slo_entry.fetch(:action)
      assert_equal 'generated-slo-1', slo_entry.dig(:attempts, 0, :result, :provider_resource_id)
      assert_equal [{ method: 'PUT', path: '/api/v1/slo/generated-slo-1' }],
                   slo_entry.dig(:attempts, 0, :result, :requests)
      assert_equal 'succeeded', slo_entry.dig(:verification, :status)

      refute_equal old_monitor_id, monitor_entry.dig(:attempts, 0, :result, :provider_resource_id)
      assert_equal [
        { method: 'DELETE', path: "/api/v1/monitor/#{old_monitor_id}" },
        { method: 'POST', path: '/api/v1/monitor' }
      ], monitor_entry.dig(:attempts, 0, :result, :requests)
      assert_equal 'succeeded', monitor_entry.dig(:verification, :status)
      assert_equal 'succeeded', plan.to_h.dig(:execution, :result, :status)
    end
  end

  def test_repeated_converged_datadog_apply_reuses_noop_journal
    Dir.mktmpdir do |dir|
      client = FakeDatadogClient.new
      applier = journaled_applier(client, dir)
      applier.apply(@manifest)

      first = applier.apply(@manifest).to_h.fetch(:execution)
      repeated = applier.apply(@manifest).to_h.fetch(:execution)

      assert_equal 'noop', first.dig(:result, :status)
      assert_equal 'not_required', first.dig(:result, :verification, :status)
      assert_equal first.dig(:operation_journal, :journal_id),
                   repeated.dig(:operation_journal, :journal_id)
      assert_equal first.dig(:operation_journal, :path),
                   repeated.dig(:operation_journal, :path)
    end
  end

  private

  class FailingMonitorClient < FakeDatadogClient
    def request(method, path, payload: nil)
      if method == 'POST' && path == '/api/v1/monitor'
        raise SloRulesEngine::Datadog::ApiError.new(
          'backend rejected authorization token=secret-value',
          response: FakeResponse.new('500', '{}')
        )
      end

      super
    end
  end

  def journaled_applier(client, dir)
    tick = 0
    clock = lambda do
      value = Time.utc(2026, 7, 26, 13, 0, tick)
      tick += 1
      value
    end
    SloRulesEngine::Appliers::Datadog.new(
      client: client,
      journal_dir: File.join(dir, 'journals'),
      clock: clock
    )
  end

  def read_journal(execution)
    JSON.parse(
      File.read(execution.dig(:operation_journal, :path)),
      symbolize_names: true
    )
  end

  def managed_state_with_orphans
    {
      slos: [
        {
          id: 'slo-orphan',
          name: 'checkout-api orphan slo',
          source: 'orphan.slos[0]'
        }
      ],
      monitors: [
        {
          id: 999,
          name: 'SLO burn rate: checkout-api/orphan-sli/orphan-instance/orphan-slo',
          source: 'orphan.monitors[0]'
        }
      ],
      dashboards: [
        {
          id: 'dashboard-orphan',
          title: 'checkout-api orphan dashboard',
          source: 'orphan.dashboards[0]'
        }
      ]
    }
  end
end
