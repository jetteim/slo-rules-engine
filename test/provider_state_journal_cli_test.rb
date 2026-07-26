# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require_relative '../lib/slo_rules_engine'

class ProviderStateJournalCliTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def test_create_writes_deterministic_journal_and_status_reads_it
    Dir.mktmpdir do |dir|
      plan_path = File.join(dir, 'plan.json')
      journal_path = File.join(dir, 'journal.json')
      File.write(plan_path, JSON.pretty_generate([plan_wrapper]))

      first, first_stderr, first_status = command(
        'journal',
        'create',
        plan_path,
        "--output=#{journal_path}"
      )
      second, second_stderr, second_status = command(
        'journal',
        'create',
        plan_path,
        "--output=#{journal_path}"
      )
      status, status_stderr, status_result = command('journal', 'status', journal_path)

      assert first_status.success?, first_stderr
      assert second_status.success?, second_stderr
      assert status_result.success?, status_stderr
      assert_equal first, second
      assert_equal first, JSON.parse(File.read(journal_path))
      assert_equal 'pending', status.fetch('status')
      assert_equal true, status.fetch('valid')
      assert_equal first.fetch('journal_id'), status.fetch('journal_id')
    end
  end

  def test_create_rejects_conflicting_existing_output
    Dir.mktmpdir do |dir|
      plan_path = File.join(dir, 'plan.json')
      journal_path = File.join(dir, 'journal.json')
      File.write(plan_path, JSON.pretty_generate(plan_wrapper))
      File.write(journal_path, JSON.pretty_generate(existing: 'unrelated'))
      original = File.binread(journal_path)

      payload, _stderr, result = command(
        'journal',
        'create',
        plan_path,
        "--output=#{journal_path}"
      )

      refute result.success?
      assert_equal 'journal_output_conflict', payload.fetch('error').fetch('code')
      assert_equal original, File.binread(journal_path)
    end
  end

  def test_create_rejects_a_tampered_plan_without_writing_output
    Dir.mktmpdir do |dir|
      plan_path = File.join(dir, 'plan.json')
      journal_path = File.join(dir, 'journal.json')
      payload = plan_wrapper
      payload[:state_contract][:desired_state][:resources][:manifest][:provider] = 'tampered'
      File.write(plan_path, JSON.pretty_generate(payload))

      response, _stderr, result = command(
        'journal',
        'create',
        plan_path,
        "--output=#{journal_path}"
      )

      refute result.success?
      assert_equal 'invalid_provider_plan', response.fetch('error').fetch('code')
      refute File.exist?(journal_path)
    end
  end

  private

  def plan_wrapper
    desired = SloRulesEngine::ProviderState::DesiredState.new(
      provider: 'prometheus_stack',
      service: 'checkout-api',
      source: 'provider_manifest',
      resources: {
        manifest: {
          provider: 'prometheus_stack'
        }
      }
    )
    observed = SloRulesEngine::ProviderState::ObservedState.new(
      provider: 'prometheus_stack',
      service: 'checkout-api',
      source: 'manifest_bundle',
      resources: {
        files: []
      }
    )
    change = SloRulesEngine::ProviderState::Change.new(
      action: 'write',
      target: 'manifest_file',
      name: 'manifest.json',
      source: 'manifest',
      desired: {
        path: '/managed/checkout-api/prometheus_stack/manifest.json'
      },
      changed_paths: ['content']
    )
    state_plan = SloRulesEngine::ProviderState::Plan.new(
      provider: 'prometheus_stack',
      service: 'checkout-api',
      mode: 'dry_run',
      desired_state: desired,
      observed_state: observed,
      changes: [change],
      findings: [],
      summary: {
        total_operations: 1,
        actionable_operations: 1,
        destructive_operations: 0
      }
    )
    {
      provider: 'prometheus_stack',
      service: 'checkout-api',
      mode: 'dry_run',
      operations: [
        {
          action: 'write',
          target: 'manifest_file',
          name: 'manifest.json',
          source: 'manifest'
        }
      ],
      state_contract: state_plan.to_h
    }
  end

  def command(*argv)
    stdout, stderr, status = Open3.capture3('ruby', File.join(ROOT, 'bin', 'rules-ctl'), *argv)
    [JSON.parse(stdout), stderr, status]
  end
end
