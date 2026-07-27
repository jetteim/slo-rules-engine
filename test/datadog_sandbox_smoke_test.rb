# frozen_string_literal: true

require 'minitest/autorun'
require 'open3'
require 'rbconfig'
require_relative '../lib/slo_rules_engine'

class DatadogSandboxSmokeTest < Minitest::Test
  class FakeClient
    attr_reader :requests, :desired_states, :deleted_ids

    def initialize(catalog:, details: {}, created_id: 'sandbox-dashboard-1', states: [])
      @catalog = catalog
      @details = details
      @created_id = created_id
      @states = states
      @requests = []
      @desired_states = []
      @deleted_ids = []
    end

    def validate_credentials!
      true
    end

    def request(method, path, payload: nil, **_options)
      @requests << { method: method, path: path, payload: payload }
      return { 'valid' => true } if path == '/api/v1/validate'
      return { 'dashboards' => @catalog } if path == '/api/v1/dashboard?count=100&start=0'
      return { 'id' => @created_id } if method == 'POST' && path == '/api/v1/dashboard'

      @details.fetch(path)
    end

    def existing_state(desired:)
      @desired_states << desired
      @states.shift || { dashboards: {} }
    end

    def delete_dashboard(id)
      @deleted_ids << id
      nil
    end
  end

  def test_read_only_smoke_validates_credentials_catalog_and_detail
    client = FakeClient.new(
      catalog: [{ 'id' => 'dashboard-123', 'title' => 'Existing dashboard' }],
      details: {
        '/api/v1/dashboard/dashboard-123' => {
          'id' => 'dashboard-123',
          'title' => 'Existing dashboard',
          'tags' => [],
          'widgets' => []
        }
      }
    )

    report = smoke(client).run

    assert_equal 'passed', report.fetch(:status)
    assert_equal 'read_only', report.fetch(:mode)
    assert_equal %w[
      credentials_present
      api_key_validation
      dashboard_catalog
      dashboard_detail
    ], report.fetch(:checks).map { |check| check.fetch(:name) }
    assert_equal 'not_requested', report.fetch(:mutation).fetch(:status)
    assert_empty client.deleted_ids
  end

  def test_read_only_smoke_skips_detail_when_catalog_is_empty
    report = smoke(FakeClient.new(catalog: [])).run

    detail = report.fetch(:checks).find { |check| check.fetch(:name) == 'dashboard_detail' }
    assert_equal 'skipped', detail.fetch(:status)
    assert_equal 'empty_catalog', detail.fetch(:reason)
  end

  def test_mutation_smoke_creates_finds_and_deletes_one_managed_dashboard
    title = 'slo-rules-engine sandbox smoke smoke-token'
    client = FakeClient.new(
      catalog: [],
      states: [
        {
          dashboards: {
            title => {
              id: 'sandbox-dashboard-1',
              match_identity: { strategy: 'source_ref', confidence: 'high' }
            }
          }
        },
        { dashboards: {} }
      ]
    )

    report = smoke(client).run(allow_mutation: true)

    mutation = report.fetch(:mutation)
    assert_equal 'passed', mutation.fetch(:status)
    assert_equal 'sandbox-dashboard-1', mutation.fetch(:provider_resource_id)
    assert_equal 'sandbox_smoke.smoke-token', mutation.fetch(:source_ref)
    assert_equal ['sandbox-dashboard-1'], client.deleted_ids
    assert_equal 2, client.desired_states.length

    create = client.requests.find { |request| request.fetch(:method) == 'POST' }
    assert_equal '/api/v1/dashboard', create.fetch(:path)
    assert_equal title, create.fetch(:payload).fetch(:title)
    assert_includes create.fetch(:payload).fetch(:tags), 'managed_by:slo-rules-engine'
    assert_includes create.fetch(:payload).fetch(:tags), 'service:slo-rules-engine-sandbox'
    assert_includes create.fetch(:payload).fetch(:tags), 'source_ref:sandbox_smoke.smoke-token'
  end

  def test_mutation_smoke_attempts_cleanup_when_reconciliation_fails
    client = FakeClient.new(catalog: [], states: Array.new(3) { { dashboards: {} } })

    error = assert_raises(SloRulesEngine::Datadog::SandboxSmoke::ContractError) do
      smoke(client, attempts: 3).run(allow_mutation: true)
    end

    assert_equal 'dashboard_not_found_after_create', error.code
    assert_equal ['sandbox-dashboard-1'], client.deleted_ids
  end

  def test_command_fails_safely_without_credentials
    command = File.expand_path('../scripts/datadog-sandbox-smoke', __dir__)
    stdout, stderr, status = Open3.capture3(
      { 'DD_API_KEY' => nil, 'DD_APP_KEY' => nil },
      RbConfig.ruby,
      command
    )

    report = JSON.parse(stdout)
    refute status.success?
    assert_empty stderr
    assert_equal 'missing_credentials', report.fetch('finding').fetch('code')
    refute_includes stdout, 'DD_API_KEY'
    refute_includes stdout, 'DD_APP_KEY'
  end

  private

  def smoke(client, attempts: 2)
    SloRulesEngine::Datadog::SandboxSmoke.new(
      client: client,
      site: 'datadoghq.eu',
      token: 'smoke-token',
      attempts: attempts,
      sleep_fn: ->(_seconds) {}
    )
  end
end
