# frozen_string_literal: true

require 'json'
require 'net/http'
require 'time'
require 'timeout'
require 'uri'

module SloRulesEngine
  module Sloth
    module Mcp
      class RuntimeConfig
        attr_reader :endpoint, :allowed_hosts, :expected_version, :from, :to, :page_size,
                    :max_pages, :max_series_points, :timeout_seconds, :max_response_bytes

        def initialize(endpoint:, allowed_hosts:, expected_version:, from:, to:, page_size: 100,
                       max_pages: 10, max_series_points: 1_000, timeout_seconds: 10,
                       max_response_bytes: 1_048_576)
          @endpoint = parse_endpoint(endpoint)
          @allowed_hosts = Array(allowed_hosts).map { |host| host.to_s.downcase }.uniq.sort
          @expected_version = expected_version.to_s
          @from = parse_time(from, 'from')
          @to = parse_time(to, 'to')
          @page_size = integer_in_range(page_size, 'page_size', 1..100)
          @max_pages = integer_in_range(max_pages, 'max_pages', 1..50)
          @max_series_points = integer_in_range(max_series_points, 'max_series_points', 1..10_000)
          @timeout_seconds = integer_in_range(timeout_seconds, 'timeout_seconds', 1..60)
          @max_response_bytes = integer_in_range(
            max_response_bytes,
            'max_response_bytes',
            1_024..10_485_760
          )
          validate!
          freeze
        end

        private

        def parse_endpoint(value)
          URI.parse(value.to_s)
        rescue URI::InvalidURIError
          invalid_runtime!('invalid_sloth_mcp_endpoint', 'Sloth MCP endpoint must be a valid URL.')
        end

        def parse_time(value, name)
          Time.iso8601(value.to_s).utc
        rescue ArgumentError
          invalid_runtime!('invalid_sloth_mcp_range', "Sloth MCP #{name} must be ISO 8601.")
        end

        def integer_in_range(value, name, range)
          number = Integer(value)
          return number if range.cover?(number)

          invalid_runtime!(
            'invalid_sloth_mcp_bounds',
            "Sloth MCP #{name} must be between #{range.begin} and #{range.end}."
          )
        rescue ArgumentError, TypeError
          invalid_runtime!('invalid_sloth_mcp_bounds', "Sloth MCP #{name} must be an integer.")
        end

        def validate!
          valid_endpoint = %w[http https].include?(endpoint.scheme) &&
            !endpoint.host.to_s.empty? && endpoint.userinfo.nil? &&
            endpoint.query.nil? && endpoint.fragment.nil?
          invalid_runtime!('invalid_sloth_mcp_endpoint', 'Sloth MCP endpoint must use HTTP(S), include a host, and exclude credentials, query, and fragment.') unless valid_endpoint
          if allowed_hosts.empty? || allowed_hosts.any? { |host| host.empty? || host.include?('/') }
            invalid_runtime!('invalid_sloth_mcp_allowlist', 'At least one valid Sloth MCP host allowlist entry is required.')
          end
          unless allowed_hosts.include?(endpoint.host.downcase)
            invalid_runtime!('sloth_mcp_endpoint_not_allowed', 'Sloth MCP endpoint host is not in the explicit allowlist.')
          end
          unless SUPPORTED_VERSIONS.key?(expected_version)
            invalid_runtime!(
              'unsupported_sloth_mcp_version',
              'Sloth MCP runtime version is not in the tested capability matrix.',
              expected_version: expected_version,
              supported_versions: SUPPORTED_VERSIONS.keys.sort
            )
          end
          invalid_runtime!('invalid_sloth_mcp_range', 'Sloth MCP range must end after it starts.') unless to > from
          if (to - from) > (366 * 86_400)
            invalid_runtime!('invalid_sloth_mcp_range', 'Sloth MCP comparison range cannot exceed 366 days.')
          end
        end

        def invalid_runtime!(code, message, details = {})
          raise ContractError.new(code, message, findings: [Support.finding(code, message, details)])
        end
      end

      class RequestTransport
        Response = Struct.new(:status, :body, keyword_init: true)

        def post(uri, payload, protocol_version:, timeout_seconds:, max_response_bytes:)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == 'https'
          http.open_timeout = timeout_seconds
          http.read_timeout = timeout_seconds
          http.write_timeout = timeout_seconds if http.respond_to?(:write_timeout=)
          request = Net::HTTP::Post.new(uri.request_uri.empty? ? '/' : uri.request_uri)
          request['Content-Type'] = 'application/json'
          request['Accept'] = 'application/json, text/event-stream'
          request['MCP-Protocol-Version'] = protocol_version if protocol_version
          request.body = JSON.generate(payload)
          status = nil
          body = +''
          http.request(request) do |response|
            status = response.code.to_i
            response.read_body do |chunk|
              body << chunk
              if body.bytesize > max_response_bytes
                raise ContractError.new(
                  'sloth_mcp_response_too_large',
                  'Sloth MCP response exceeded the configured byte limit.',
                  findings: [Support.finding(
                    'sloth_mcp_response_too_large',
                    'Sloth MCP response exceeded the configured byte limit.',
                    max_response_bytes: max_response_bytes
                  )]
                )
              end
            end
          end
          Response.new(status: status, body: body)
        rescue ContractError
          raise
        rescue SystemCallError, IOError, Timeout::Error, SocketError => error
          raise ContractError.new(
            'sloth_mcp_transport_failed',
            'Sloth MCP request failed.',
            findings: [Support.finding(
              'sloth_mcp_transport_failed',
              'Sloth MCP request failed.',
              error_class: error.class.name
            )]
          )
        end
      end

      class Client
        def initialize(config:, transport: RequestTransport.new)
          @config = config
          @transport = transport
          @next_id = 0
          @protocol_version = nil
          @connected = false
        end

        def connect
          initialization = rpc(
            'initialize',
            {
              protocolVersion: PROTOCOL_VERSION,
              capabilities: {},
              clientInfo: { name: 'slo-rules-engine', version: '1' }
            },
            protocol_version: nil
          )
          protocol = Support.fetch_value(initialization, :protocolVersion).to_s
          server = Support.fetch_value(initialization, :serverInfo, {})
          notify_initialized(protocol)
          tools_result = rpc('tools/list', {}, protocol_version: protocol)
          @protocol_version = protocol
          @connected = true
          {
            protocol_version: protocol,
            server_info: {
              name: Support.fetch_value(server, :name).to_s,
              version: Support.fetch_value(server, :version).to_s
            },
            tools: Array(Support.fetch_value(tools_result, :tools)),
            next_cursor: Support.fetch_value(tools_result, :nextCursor)
          }
        end

        def call_tool(name, arguments = {})
          raise ContractError.new('sloth_mcp_not_initialized', 'Sloth MCP client is not initialized.') unless @connected
          unless TOOL_CONTRACTS.key?(name)
            raise ContractError.new(
              'unsafe_sloth_mcp_tool',
              'Attempted tool is outside the read-only allowlist.',
              findings: [Support.finding(
                'unsafe_sloth_mcp_tool',
                'Attempted tool is outside the read-only allowlist.',
                tool: name
              )]
            )
          end

          result = rpc(
            'tools/call',
            { name: name, arguments: arguments },
            protocol_version: @protocol_version
          )
          if Support.fetch_value(result, :isError) == true
            raise ContractError.new(
              'sloth_mcp_tool_failed',
              'Sloth MCP read-only tool returned an error.',
              findings: [Support.finding(
                'sloth_mcp_tool_failed',
                'Sloth MCP read-only tool returned an error.',
                tool: name
              )]
            )
          end
          structured = Support.fetch_value(result, :structuredContent)
          unless structured.is_a?(Hash)
            raise ContractError.new(
              'invalid_sloth_mcp_tool_result',
              'Sloth MCP tool result must contain structured content.',
              findings: [Support.finding(
                'invalid_sloth_mcp_tool_result',
                'Sloth MCP tool result must contain structured content.',
                tool: name
              )]
            )
          end

          structured
        end

        private

        def notify_initialized(protocol)
          response = @transport.post(
            @config.endpoint,
            { jsonrpc: '2.0', method: 'notifications/initialized', params: {} },
            protocol_version: protocol,
            timeout_seconds: @config.timeout_seconds,
            max_response_bytes: @config.max_response_bytes
          )
          return if [200, 202, 204].include?(response.status)

          http_error!(response.status)
        end

        def rpc(method, params, protocol_version:)
          id = next_id
          response = @transport.post(
            @config.endpoint,
            { jsonrpc: '2.0', id: id, method: method, params: params },
            protocol_version: protocol_version,
            timeout_seconds: @config.timeout_seconds,
            max_response_bytes: @config.max_response_bytes
          )
          http_error!(response.status) unless response.status == 200
          if response.body.bytesize > @config.max_response_bytes
            raise ContractError.new(
              'sloth_mcp_response_too_large',
              'Sloth MCP response exceeded the configured byte limit.',
              findings: [Support.finding(
                'sloth_mcp_response_too_large',
                'Sloth MCP response exceeded the configured byte limit.',
                max_response_bytes: @config.max_response_bytes
              )]
            )
          end
          envelope = JSON.parse(response.body)
          unless envelope.is_a?(Hash) && envelope['jsonrpc'] == '2.0' && envelope['id'] == id
            invalid_envelope!
          end
          if envelope['error']
            code = Support.fetch_value(envelope['error'], :code)
            raise ContractError.new(
              'sloth_mcp_rpc_error',
              'Sloth MCP returned a JSON-RPC error.',
              findings: [Support.finding(
                'sloth_mcp_rpc_error',
                'Sloth MCP returned a JSON-RPC error.',
                rpc_code: code,
                method: method
              )]
            )
          end
          result = envelope['result']
          invalid_envelope! unless result.is_a?(Hash)

          result
        rescue JSON::ParserError
          invalid_envelope!
        end

        def next_id
          @next_id += 1
        end

        def http_error!(status)
          raise ContractError.new(
            'sloth_mcp_http_error',
            'Sloth MCP returned an unsuccessful HTTP response.',
            findings: [Support.finding(
              'sloth_mcp_http_error',
              'Sloth MCP returned an unsuccessful HTTP response.',
              status: status
            )]
          )
        end

        def invalid_envelope!
          raise ContractError.new(
            'invalid_sloth_mcp_response',
            'Sloth MCP returned an invalid JSON-RPC response.',
            findings: [Support.finding(
              'invalid_sloth_mcp_response',
              'Sloth MCP returned an invalid JSON-RPC response.'
            )]
          )
        end
      end
    end
  end
end
