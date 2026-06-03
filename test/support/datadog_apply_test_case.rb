# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../lib/slo_rules_engine'
require_relative 'datadog_fakes'

class DatadogApplyTest < Minitest::Test
  def setup
    SloRulesEngine.clear_definitions
    load File.expand_path('../../examples/services/checkout.rb', __dir__)
    @definition = SloRulesEngine.definitions.fetch(0)
    @manifest = SloRulesEngine.default_provider_registry.fetch('datadog')
      .generate(@definition)
      .to_h
      .merge(service: @definition.service)
  end

  private

  def time_slice_manifest
    manifest = Marshal.load(Marshal.dump(@manifest))
    manifest.fetch(:artifacts).fetch(:slos).fetch(0).merge!(
      calculation_basis: 'time_slice',
      query: {
        data_source: 'datadog',
        metric: 'http.server.request.duration',
        type: 'counter',
        range: '5m',
        selector: {
          service: 'checkout-api',
          route: '/checkout'
        },
        success_selector: {
          status: 'success'
        }
      }
    )
    manifest
  end

  def threshold_time_slice_manifest
    manifest = Marshal.load(Marshal.dump(@manifest))
    manifest.fetch(:artifacts).fetch(:slos).fetch(0).merge!(
      calculation_basis: 'time_slice',
      query: {
        data_source: 'datadog',
        metric: 'http.server.request.duration',
        type: 'distribution',
        range: '5m',
        selector: {
          service: 'checkout-api',
          route: '/checkout'
        },
        query: 'p95:http.server.request.duration{service:checkout-api}',
        success_threshold: {
          operator: '<=',
          value: '0.3'
        }
      }
    )
    manifest
  end

  def inferred_distribution_time_slice_manifest
    manifest = threshold_time_slice_manifest
    manifest.fetch(:artifacts).fetch(:slos).fetch(0).fetch(:query).delete(:query)
    manifest
  end

  def inferred_gauge_time_slice_manifest
    manifest = Marshal.load(Marshal.dump(@manifest))
    manifest.fetch(:artifacts).fetch(:slos).fetch(0).merge!(
      calculation_basis: 'time_slice',
      query: {
        data_source: 'datadog',
        metric: 'worker.queue.depth',
        type: 'gauge',
        range: '5m',
        selector: {
          service: 'checkout-api',
          queue: 'default'
        },
        success_threshold: {
          operator: '<=',
          value: '5'
        }
      }
    )
    manifest
  end

  def inferred_counter_time_slice_manifest
    manifest = Marshal.load(Marshal.dump(@manifest))
    manifest.fetch(:artifacts).fetch(:slos).fetch(0).merge!(
      calculation_basis: 'time_slice',
      query: {
        data_source: 'datadog',
        metric: 'http.server.request.count',
        type: 'counter',
        range: '5m',
        selector: {
          service: 'checkout-api',
          route: '/checkout'
        },
        success_threshold: {
          operator: '>=',
          value: '10'
        }
      }
    )
    manifest
  end

  class RetryHttp
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def start(_host, _port, use_ssl:)
      raise 'expected TLS for Datadog API' unless use_ssl

      yield self
    end

    def request(request)
      @requests << request
      @responses.shift
    end
  end

  class ConnectionResetHttp
    attr_reader :request_count

    def initialize(responses)
      @responses = responses
      @request_count = 0
    end

    def start(_host, _port, use_ssl:)
      raise 'expected TLS for Datadog API' unless use_ssl

      yield self
    end

    def request(_request)
      @request_count += 1
      response = @responses.shift
      raise response if response.is_a?(Class) && response <= SystemCallError
      raise response if response.is_a?(Exception)

      response
    end
  end

  class RoutingHttp
    def initialize(routes)
      @routes = routes
    end

    def start(_host, _port, use_ssl:)
      raise 'expected TLS for Datadog API' unless use_ssl

      yield self
    end

    def request(request)
      response = @routes.fetch(request.path) do
        raise "unexpected Datadog request path #{request.path}"
      end
      response
    end
  end

  class SequencedRoutingHttp
    def initialize(routes)
      @routes = routes
    end

    def start(_host, _port, use_ssl:)
      raise 'expected TLS for Datadog API' unless use_ssl

      yield self
    end

    def request(request)
      responses = @routes.fetch(request.path) do
        raise "unexpected Datadog request path #{request.path}"
      end
      raise "no response left for Datadog request path #{request.path}" if responses.empty?

      responses.shift
    end
  end

end
