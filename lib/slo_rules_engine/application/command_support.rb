# frozen_string_literal: true

module SloRulesEngine
  module Application
    class Context
      attr_reader :provider_registry, :integration_registry, :input_policy, :network_policy, :resource_policy,
                  :telemetry_adapter_factory

      def initialize(provider_registry:, integration_registry:, input_policy: InputSafety::PathPolicy.human,
                     network_policy: nil, resource_policy: InputSafety::ResourcePolicy.new,
                     telemetry_adapter_factory: nil)
        @provider_registry = provider_registry
        @integration_registry = integration_registry
        @input_policy = input_policy
        @network_policy = network_policy || if input_policy.confined?
                                            InputSafety::NetworkPolicy.agent
                                          else
                                            InputSafety::NetworkPolicy.human
                                          end
        @resource_policy = resource_policy
        @telemetry_adapter_factory = telemetry_adapter_factory
      end
    end

    class CommandError < ArgumentError
      attr_reader :code, :details

      def initialize(code, message, details = {})
        @code = code
        @details = details
        super(message)
      end
    end

    class CommandResult
      attr_reader :value, :side_effect, :findings, :artifacts, :exit_status, :truncation

      def initialize(value:, side_effect: 'none', findings: [], artifacts: [], exit_status: 0, truncation: nil)
        @value = value
        @side_effect = side_effect
        @findings = findings.freeze
        @artifacts = artifacts.freeze
        @exit_status = exit_status
        @truncation = truncation || { truncated: false, returned: nil, limit: nil, cursor: nil }
        freeze
      end
    end
  end
end
