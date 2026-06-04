# frozen_string_literal: true

require 'minitest/autorun'
require 'uri'
require_relative '../lib/slo_rules_engine'

class DatadogStateReaderTest < Minitest::Test
  class FakeRequester
    attr_reader :requests

    def initialize(routes)
      @routes = routes
      @requests = []
    end

    def request(method, path)
      @requests << [method, path]
      @routes.fetch(path) { raise "unexpected request #{method} #{path}" }
    end
  end

  def test_reads_existing_monitor_state_by_source_ref
    source_query = URI.encode_www_form(monitor_tags: 'managed_by:slo-rules-engine,source_ref:artifacts.monitors.0')
    requester = FakeRequester.new(
      "/api/v1/monitor?#{source_query}" => [
        {
          id: 456,
          name: 'legacy monitor',
          tags: ['managed_by:slo-rules-engine', 'source_ref:artifacts.monitors.0']
        }
      ],
      '/api/v1/monitor/456' => {
        id: 456,
        name: 'legacy monitor',
        type: 'slo alert',
        query: 'burn_rate("slo-123").over("30d") > 14.4',
        tags: ['managed_by:slo-rules-engine', 'source_ref:artifacts.monitors.0']
      }
    )
    reader = SloRulesEngine::Datadog::StateReader.new(requester: requester)

    state = reader.existing_state(
      desired: {
        monitors: [
          { name: 'desired monitor', source: 'artifacts.monitors[0]' }
        ]
      }
    )

    monitor = state.fetch(:monitors).fetch('desired monitor')
    assert_equal 456, monitor.fetch(:id)
    assert_equal 'source_ref', monitor.fetch(:match_identity).fetch(:strategy)
    assert_equal 'high', monitor.fetch(:match_identity).fetch(:confidence)
    assert_equal [['GET', "/api/v1/monitor?#{source_query}"], ['GET', '/api/v1/monitor/456']], requester.requests
  end
end
