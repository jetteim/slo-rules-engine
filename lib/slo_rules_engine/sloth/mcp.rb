# frozen_string_literal: true

module SloRulesEngine
  module Sloth
    module Mcp
      SCHEMA_VERSION = 'slo-rules-engine/sloth-mcp-comparison/v1'
      KIND = 'SlothMcpComparison'
      PROTOCOL_VERSION = '2025-11-25'
      UPSTREAM_REVISION = '8a3be4fab79defa4448d09d91b48422615980b05'
      SUPPORTED_VERSIONS = {
        'dev' => {
          upstream_revision: UPSTREAM_REVISION,
          release_status: 'main_only'
        }
      }.freeze
      TOOL_CONTRACTS = {
        'context' => {
          input: {}, required: [], output: { version: 'string', description: 'string' }
        },
        'list_services' => {
          input: { search: 'string', size: 'integer', sort: 'string', cursor: 'string' },
          required: [], output: { services: %w[null array], pagination: 'object' }
        },
        'list_slos' => {
          input: {
            service_id: 'string', search: 'string', alert_firing: 'boolean',
            period_budget_consumed: 'boolean', current_burning_budget_over_100: 'boolean',
            size: 'integer', sort: 'string', cursor: 'string'
          },
          required: [], output: { slos: %w[null array], pagination: 'object' }
        },
        'get_slo' => {
          input: { slo_id: 'string' }, required: ['slo_id'], output: { slo: 'object' }
        },
        'get_slo_burned_budget_range' => {
          input: { slo_id: 'string', range_type: 'string' }, required: ['slo_id'],
          output: {
            current_burned_value_percent: 'number',
            current_expected_burned_value_percent: 'number',
            start_ts: 'string', step: 'string', real_series: 'string', perfect_series: 'string'
          }
        },
        'get_slo_sli_availability_range' => {
          input: { slo_id: 'string', from: 'string', to: 'string' },
          required: %w[slo_id from],
          output: { start_ts: 'string', step: 'string', availability_series: 'string' }
        }
      }.freeze

      class ContractError < StandardError
        attr_reader :code, :findings

        def initialize(code, message, findings: [])
          @code = code
          @findings = findings
          super(message)
        end
      end

      module Support
        module_function

        def fetch_value(container, key, default = nil)
          return container[key] if container.is_a?(Hash) && container.key?(key)
          return container[key.to_s] if container.is_a?(Hash) && container.key?(key.to_s)

          default
        end

        def finding(code, message, details = {})
          { code: code, severity: 'error', message: message }.merge(details)
        end

        def fingerprint(value)
          SloRulesEngine::ReleaseBundle::Fingerprint.content(value)
        end

        def comparison_id(report)
          identity = JSON.parse(JSON.generate(report))
          identity.delete('comparison_id')
          "sloth-mcp-comparison-#{fingerprint(identity)}"
        end
      end
    end
  end
end
