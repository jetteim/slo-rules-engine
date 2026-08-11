# frozen_string_literal: true

module SlothMcpFixtures
  MCP_PROTOCOL_VERSION = '2025-11-25'
  MCP_VERSION = 'dev'
  MCP_SERVICE = 'checkout-api'
  MCP_SLOTH_ID = 'checkout-api-http-requests-public-api-successful-requests'
  MCP_SLO_ID = 'provider-slo-1'

  def sloth_mcp_tools
    [
      tool_contract('context', {}, { version: 'string', description: 'string' }),
      tool_contract(
        'list_services',
        { search: 'string', size: 'integer', sort: 'string', cursor: 'string' },
        { services: %w[null array], pagination: 'object' }
      ),
      tool_contract(
        'list_slos',
        {
          service_id: 'string', search: 'string', alert_firing: 'boolean',
          period_budget_consumed: 'boolean', current_burning_budget_over_100: 'boolean',
          size: 'integer', sort: 'string', cursor: 'string'
        },
        { slos: %w[null array], pagination: 'object' }
      ),
      tool_contract('get_slo', { slo_id: 'string' }, { slo: 'object' }, required: %w[slo_id]),
      tool_contract(
        'get_slo_burned_budget_range',
        { slo_id: 'string', range_type: 'string' },
        {
          current_burned_value_percent: 'number',
          current_expected_burned_value_percent: 'number',
          start_ts: 'string', step: 'string', real_series: 'string', perfect_series: 'string'
        },
        required: %w[slo_id]
      ),
      tool_contract(
        'get_slo_sli_availability_range',
        { slo_id: 'string', from: 'string', to: 'string' },
        { start_ts: 'string', step: 'string', availability_series: 'string' },
        required: %w[slo_id from]
      )
    ]
  end

  def sloth_mcp_slo(objective: 99.9, period: '720h0m0s', grouped: false)
    {
      'id' => MCP_SLO_ID,
      'sloth_id' => MCP_SLOTH_ID,
      'service_id' => MCP_SERVICE,
      'objective' => objective,
      'period' => period,
      'is_grouped' => grouped,
      'burning_budget_percent' => 20.0,
      'burned_budget_window_percent' => 10.0,
      'has_page_alert' => false,
      'has_warning_alert' => false
    }
  end

  def sloth_mcp_outputs(objective: 99.9, period: '720h0m0s', grouped: false)
    slo = sloth_mcp_slo(objective: objective, period: period, grouped: grouped)
    {
      'context' => {
        'version' => MCP_VERSION,
        'description' => 'provider-controlled text is intentionally discarded'
      },
      'list_services' => {
        'services' => [
          {
            'id' => MCP_SERVICE,
            'total_slos' => 1,
            'slos_currently_burning_over_budget' => 0,
            'total_alerts_firing' => 0,
            'has_warning' => false,
            'has_critical' => false
          }
        ],
        'pagination' => empty_pagination
      },
      'list_slos' => {
        'slos' => [slo],
        'pagination' => empty_pagination
      },
      'get_slo' => { 'slo' => slo },
      'get_slo_burned_budget_range' => {
        'current_burned_value_percent' => 90.0,
        'current_expected_burned_value_percent' => 95.0,
        'start_ts' => '2026-08-01T00:00:00Z',
        'step' => '24h0m0s',
        'real_series' => '100,95,x,90',
        'perfect_series' => '100,98,96,94'
      },
      'get_slo_sli_availability_range' => {
        'start_ts' => '2026-08-01T00:00:00Z',
        'step' => '24h0m0s',
        'availability_series' => '99.99,99.98,x,99.97'
      }
    }
  end

  def empty_pagination
    {
      'next_cursor' => '',
      'prev_cursor' => '',
      'has_next' => false,
      'has_previous' => false
    }
  end

  def tool_contract(name, input_properties, output_properties = nil, required: [])
    output_properties ||= input_properties
    input_properties = {} if name == 'context'
    {
      'name' => name,
      'annotations' => { 'readOnlyHint' => true },
      'inputSchema' => schema(input_properties, required: required),
      'outputSchema' => schema(output_properties)
    }
  end

  def schema(properties, required: [])
    {
      'type' => 'object',
      'properties' => properties.to_h do |name, type|
        [name.to_s, { 'type' => type }]
      end,
      'required' => required
    }
  end

  class FakeSlothMcpClient
    attr_reader :calls

    def initialize(tools:, outputs:, version: MCP_VERSION, protocol_version: MCP_PROTOCOL_VERSION)
      @tools = tools
      @outputs = outputs
      @version = version
      @protocol_version = protocol_version
      @calls = []
    end

    def connect
      {
        protocol_version: @protocol_version,
        server_info: { name: 'sloth', version: @version },
        tools: @tools
      }
    end

    def call_tool(name, arguments = {})
      @calls << [name, arguments]
      output = @outputs.fetch(name)
      output.respond_to?(:call) ? output.call(arguments) : Marshal.load(Marshal.dump(output))
    end
  end
end
