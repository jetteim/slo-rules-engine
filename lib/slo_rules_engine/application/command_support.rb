# frozen_string_literal: true

module SloRulesEngine
  module Application
    class Context
      attr_reader :provider_registry, :integration_registry, :input_policy

      def initialize(provider_registry:, integration_registry:, input_policy: InputSafety::PathPolicy.human)
        @provider_registry = provider_registry
        @integration_registry = integration_registry
        @input_policy = input_policy
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
      attr_reader :value, :side_effect, :findings, :artifacts, :exit_status

      def initialize(value:, side_effect: 'none', findings: [], artifacts: [], exit_status: 0)
        @value = value
        @side_effect = side_effect
        @findings = findings.freeze
        @artifacts = artifacts.freeze
        @exit_status = exit_status
        freeze
      end
    end
  end
end
