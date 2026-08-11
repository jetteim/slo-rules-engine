# frozen_string_literal: true

require 'json'
require 'time'

module SloRulesEngine
  module Sloth
    module Mcp
      class Comparison
        SLO_ITEM_KEYS = %w[
          id sloth_id name service_id objective period is_grouped group_labels
          burning_budget_percent burned_budget_window_percent has_page_alert page_alert_name
          has_warning_alert warning_alert_name
        ].freeze
        SERVICE_ITEM_KEYS = %w[
          id total_slos slos_currently_burning_over_budget total_alerts_firing
          has_warning has_critical
        ].freeze
        ID_PATTERN = /\A[a-zA-Z0-9][a-zA-Z0-9_.:\/-]{0,255}\z/
        NUMBER_TOLERANCE = 1e-6

        def initialize(
          client_factory: ->(**options) { Client.new(**options) },
          clock: -> { Time.now.utc }
        )
          @client_factory = client_factory
          @clock = clock
        end

        def compare(manifest_path:, evidence_path:, endpoint:, allowed_hosts:, expected_version:,
                    from:, to:, page_size: 100, max_pages: 10, max_series_points: 1_000,
                    timeout_seconds: 10, max_response_bytes: 1_048_576)
          manifest, evidence = preflight_sources(manifest_path, evidence_path)
          config = RuntimeConfig.new(
            endpoint: endpoint,
            allowed_hosts: allowed_hosts,
            expected_version: expected_version,
            from: from,
            to: to,
            page_size: page_size,
            max_pages: max_pages,
            max_series_points: max_series_points,
            timeout_seconds: timeout_seconds,
            max_response_bytes: max_response_bytes
          )
          client = @client_factory.call(config: config)
          connection = client.connect
          validate_connection!(connection, config)
          context = checked_tool_call(client, 'context', {})
          validate_context!(context, connection, config)

          expected = expected_slos(evidence)
          services = paginated_tool(
            client,
            'list_services',
            item_key: 'services',
            arguments: { 'search' => Support.fetch_value(evidence, :service), 'size' => config.page_size,
                         'sort' => 'service-name-asc' },
            config: config
          )
          validate_services!(services, expected, Support.fetch_value(evidence, :service).to_s)
          listed = paginated_tool(
            client,
            'list_slos',
            item_key: 'slos',
            arguments: { 'service_id' => Support.fetch_value(evidence, :service),
                         'size' => config.page_size, 'sort' => 'slo-id-asc' },
            config: config
          )
          matched = reconcile_identities!(listed, expected)
          results = expected.keys.sort.map do |sloth_id|
            compare_slo(client, expected.fetch(sloth_id), matched.fetch(sloth_id), config)
          end
          findings = results.flat_map { |result| result.fetch(:findings) }
          report = build_report(
            manifest,
            evidence,
            connection,
            config,
            results,
            findings
          )
          credential_paths = SloRulesEngine::ReleaseBundle::CredentialScanner.paths(report, 'report')
          unless credential_paths.empty?
            raise ContractError.new(
              'credential_like_sloth_mcp_output',
              'Sloth MCP comparison output contains forbidden credential-like keys.',
              findings: credential_paths.map do |path|
                Support.finding(
                  'credential_like_sloth_mcp_output',
                  'Sloth MCP comparison output contains a forbidden credential-like key.',
                  path: path
                )
              end
            )
          end
          report[:comparison_id] = Support.comparison_id(report)
          report
        end

        private

        def preflight_sources(manifest_path, evidence_path)
          manifest = SloRulesEngine::Sloth::DownstreamEvidence::Support.json_file(manifest_path)
          preflight = SloRulesEngine::LiveStatus::SlothReader.new.preflight(
            manifest,
            evidence_path: evidence_path
          )
          [manifest, preflight.evidence]
        rescue SloRulesEngine::Sloth::DownstreamEvidence::ContractError => error
          raise ContractError.new(
            'invalid_sloth_mcp_evidence',
            'Sloth MCP comparison requires current evidence for the exact reviewed manifest.',
            findings: error.findings
          )
        rescue SloRulesEngine::ManifestSchemaError => error
          raise ContractError.new(
            'invalid_sloth_mcp_evidence',
            'Sloth MCP comparison requires a valid reviewed Sloth manifest.',
            findings: error.errors.map do |finding|
              Support.finding('invalid_sloth_manifest', finding.message, path: finding.path)
            end
          )
        end

        def validate_connection!(connection, config)
          findings = []
          protocol = Support.fetch_value(connection, :protocol_version).to_s
          if protocol != PROTOCOL_VERSION
            findings << Support.finding(
              'unsupported_sloth_mcp_protocol',
              'Sloth MCP protocol version does not match the tested contract.',
              expected: PROTOCOL_VERSION,
              actual: protocol
            )
          end
          server = Support.fetch_value(connection, :server_info, {})
          unless Support.fetch_value(server, :name).to_s == 'sloth'
            findings << Support.finding(
              'wrong_sloth_mcp_server',
              'MCP server identity must be sloth.'
            )
          end
          server_version = Support.fetch_value(server, :version).to_s
          if server_version != config.expected_version
            findings << version_finding(server_version, config.expected_version)
          end
          unless Support.fetch_value(connection, :next_cursor).to_s.empty?
            findings << Support.finding(
              'paginated_sloth_mcp_tool_inventory',
              'Sloth MCP tool inventory must fit in one complete response.'
            )
          end
          findings.concat(tool_contract_findings(Array(Support.fetch_value(connection, :tools))))
          return if findings.empty?

          raise ContractError.new(
            'invalid_sloth_mcp_contract',
            'Sloth MCP runtime does not match the pinned read-only contract.',
            findings: findings
          )
        end

        def tool_contract_findings(tools)
          findings = []
          names = tools.map { |tool| Support.fetch_value(tool, :name).to_s }
          duplicate = names.group_by(&:itself).find { |_name, entries| entries.length > 1 }&.first
          if duplicate
            findings << Support.finding(
              'duplicate_sloth_mcp_tool',
              'Sloth MCP tool names must be unique.',
              tool: duplicate
            )
          end
          (names - TOOL_CONTRACTS.keys).uniq.sort.each do |name|
            findings << Support.finding(
              'unexpected_sloth_mcp_tool',
              'Sloth MCP exposed a tool outside the pinned read-only inventory.',
              tool: name
            )
          end
          (TOOL_CONTRACTS.keys - names).sort.each do |name|
            findings << Support.finding(
              'missing_sloth_mcp_tool',
              'Sloth MCP omitted a required read-only tool.',
              tool: name
            )
          end
          tools.each do |tool|
            name = Support.fetch_value(tool, :name).to_s
            contract = TOOL_CONTRACTS[name]
            next unless contract

            annotations = Support.fetch_value(tool, :annotations, {})
            unless Support.fetch_value(annotations, :readOnlyHint) == true
              findings << Support.finding(
                'unsafe_sloth_mcp_tool',
                'Every allowed Sloth MCP tool must declare readOnlyHint.',
                tool: name
              )
            end
            unless schema_matches?(Support.fetch_value(tool, :inputSchema), contract.fetch(:input), contract.fetch(:required)) &&
                   schema_matches?(Support.fetch_value(tool, :outputSchema), contract.fetch(:output), nil)
              findings << Support.finding(
                'sloth_mcp_tool_schema_mismatch',
                'Sloth MCP tool schema does not match the pinned contract.',
                tool: name
              )
            end
          end
          findings
        end

        def schema_matches?(schema, properties, required)
          return false unless schema.is_a?(Hash) && Support.fetch_value(schema, :type) == 'object'

          actual = Support.fetch_value(schema, :properties, {})
          return false unless actual.is_a?(Hash)
          return false unless actual.keys.map(&:to_s).sort == properties.keys.map(&:to_s).sort

          types_match = properties.all? do |name, type|
            actual_type = Support.fetch_value(Support.fetch_value(actual, name, {}), :type)
            type.is_a?(Array) ? Array(actual_type) == type : actual_type.to_s == type
          end
          return false unless types_match
          return true if required.nil?

          Array(Support.fetch_value(schema, :required)).map(&:to_s).sort == required.sort
        end

        def validate_context!(context, connection, config)
          exact_keys!(context, %w[version description], 'context')
          version = Support.fetch_value(context, :version).to_s
          server_version = Support.fetch_value(Support.fetch_value(connection, :server_info, {}), :version).to_s
          return if version == config.expected_version && version == server_version

          raise ContractError.new(
            'invalid_sloth_mcp_contract',
            'Sloth MCP context version does not match the initialized runtime.',
            findings: [version_finding(version, config.expected_version)]
          )
        end

        def version_finding(actual, expected)
          Support.finding(
            'unsupported_sloth_mcp_version',
            'Sloth MCP runtime version does not match the tested capability matrix.',
            expected: expected,
            actual: actual,
            supported_versions: SUPPORTED_VERSIONS.keys.sort
          )
        end

        def paginated_tool(client, tool, item_key:, arguments:, config:)
          items = []
          cursor = nil
          seen = {}
          config.max_pages.times do |page|
            request = arguments.merge('cursor' => cursor).reject { |_key, value| value.to_s.empty? }
            result = checked_tool_call(client, tool, request)
            exact_keys!(result, [item_key, 'pagination'], tool)
            page_items = Support.fetch_value(result, item_key)
            contract_error!('invalid_sloth_mcp_tool_result', "#{tool} items must be an array.", tool: tool) unless page_items.is_a?(Array)
            items.concat(page_items)
            pagination = Support.fetch_value(result, :pagination)
            validate_pagination!(pagination, tool)
            break unless Support.fetch_value(pagination, :has_next) == true

            next_cursor = Support.fetch_value(pagination, :next_cursor).to_s
            if next_cursor.empty? || seen[next_cursor] || next_cursor == cursor
              contract_error!(
                'sloth_mcp_pagination_cycle',
                'Sloth MCP pagination cursor is missing or repeated.',
                tool: tool,
                page: page + 1
              )
            end
            seen[next_cursor] = true
            cursor = next_cursor
            if page + 1 == config.max_pages
              contract_error!(
                'sloth_mcp_page_limit_exceeded',
                'Sloth MCP pagination exceeded the configured page limit.',
                tool: tool,
                max_pages: config.max_pages
              )
            end
          end
          items
        end

        def validate_pagination!(pagination, tool)
          unless pagination.is_a?(Hash)
            contract_error!('invalid_sloth_mcp_tool_result', 'Sloth MCP pagination must be an object.', tool: tool)
          end
          allowed = %w[next_cursor prev_cursor has_next has_previous]
          unexpected = pagination.keys.map(&:to_s) - allowed
          contract_error!('invalid_sloth_mcp_tool_result', 'Sloth MCP pagination has unknown fields.', tool: tool, fields: unexpected.sort) unless unexpected.empty?
          unless [true, false].include?(Support.fetch_value(pagination, :has_next))
            contract_error!('invalid_sloth_mcp_tool_result', 'Sloth MCP pagination has_next must be boolean.', tool: tool)
          end
        end

        def validate_services!(services, expected, service_id)
          services.each { |service| exact_keys!(service, SERVICE_ITEM_KEYS, 'list_services.services[]') }
          matching = services.select { |service| Support.fetch_value(service, :id).to_s == service_id }
          unexpected = services.reject { |service| Support.fetch_value(service, :id).to_s == service_id }
          findings = []
          findings << Support.finding('missing_sloth_mcp_service', 'Sloth MCP did not return the reviewed service.') if matching.empty?
          findings << Support.finding('duplicate_sloth_mcp_service', 'Sloth MCP returned the reviewed service more than once.') if matching.length > 1
          unless unexpected.empty?
            findings << Support.finding(
              'unexpected_sloth_mcp_service',
              'Sloth MCP service search returned identities outside reviewed evidence.',
              count: unexpected.length
            )
          end
          if matching.length == 1
            total = integer_value(Support.fetch_value(matching.fetch(0), :total_slos))
            if total != expected.length
              findings << Support.finding(
                'sloth_mcp_service_slo_count_mismatch',
                'Sloth MCP service SLO count does not match reviewed evidence.',
                expected: expected.length,
                actual: total
              )
            end
          end
          identity_error!(findings) unless findings.empty?
        end

        def reconcile_identities!(listed, expected)
          listed.each { |item| validate_slo_item!(item, source: 'list_slos') }
          by_id = listed.group_by { |item| Support.fetch_value(item, :sloth_id).to_s }
          findings = []
          by_id.each do |sloth_id, items|
            if items.length > 1
              findings << Support.finding(
                'duplicate_sloth_mcp_identity',
                'Sloth MCP returned a Sloth identity more than once.',
                sloth_id: sloth_id
              )
            end
            if items.any? { |item| Support.fetch_value(item, :is_grouped) == true }
              findings << Support.finding(
                'grouped_sloth_mcp_identity',
                'Grouped Sloth MCP identities cannot be reconciled with reviewed ungrouped evidence.',
                sloth_id: sloth_id
              )
            end
          end
          missing = expected.keys - by_id.keys
          unexpected = by_id.keys - expected.keys
          findings << Support.finding('missing_sloth_mcp_identity', 'Sloth MCP omitted reviewed SLO identities.', sloth_ids: missing.sort) unless missing.empty?
          findings << Support.finding('unexpected_sloth_mcp_identity', 'Sloth MCP returned unreviewed SLO identities.', sloth_ids: unexpected.sort) unless unexpected.empty?
          identity_error!(findings) unless findings.empty?

          expected.to_h { |sloth_id, _value| [sloth_id, by_id.fetch(sloth_id).fetch(0)] }
        end

        def expected_slos(evidence)
          Array(Support.fetch_value(evidence, :slos)).to_h do |entry|
            identity = Support.fetch_value(entry, :identity, {})
            [Support.fetch_value(identity, :sloth_id).to_s, entry]
          end
        end

        def compare_slo(client, expected, listed, config)
          provider_id = Support.fetch_value(listed, :id).to_s
          details = checked_tool_call(client, 'get_slo', 'slo_id' => provider_id)
          exact_keys!(details, ['slo'], 'get_slo')
          detailed = Support.fetch_value(details, :slo)
          validate_slo_item!(detailed, source: 'get_slo')
          budget = checked_tool_call(
            client,
            'get_slo_burned_budget_range',
            'slo_id' => provider_id,
            'range_type' => range_type(config.from, config.to)
          )
          availability = checked_tool_call(
            client,
            'get_slo_sli_availability_range',
            'slo_id' => provider_id,
            'from' => config.from.iso8601,
            'to' => config.to.iso8601
          )
          budget_evidence = parse_budget_range(budget, config)
          availability_evidence = parse_availability_range(availability, config)
          findings = semantic_findings(expected, listed, detailed, budget_evidence)
          {
            uid: Support.fetch_value(expected, :uid),
            status: findings.empty? ? 'matched' : 'drift',
            identity: {
              service: Support.fetch_value(Support.fetch_value(expected, :identity, {}), :service),
              slo: Support.fetch_value(Support.fetch_value(expected, :identity, {}), :slo),
              sloth_id: Support.fetch_value(Support.fetch_value(expected, :identity, {}), :sloth_id)
            },
            reviewed: {
              objective_ratio: Support.fetch_value(Support.fetch_value(expected, :reviewed_intent, {}), :objective_ratio),
              evaluation_window: Support.fetch_value(Support.fetch_value(expected, :reviewed_intent, {}), :evaluation_window)
            },
            provider: provider_slo_evidence(listed).merge(
              burned_budget_range: budget_evidence,
              availability_range: availability_evidence
            ),
            findings: findings
          }
        end

        def semantic_findings(expected, listed, detailed, budget)
          findings = []
          intent = Support.fetch_value(expected, :reviewed_intent, {})
          reviewed_objective = Float(Support.fetch_value(intent, :objective_ratio))
          listed_objective = numeric_value(Support.fetch_value(listed, :objective)) / 100.0
          unless close?(reviewed_objective, listed_objective)
            findings << Support.finding(
              'sloth_mcp_objective_mismatch',
              'Sloth MCP objective does not match reviewed evidence.',
              reviewed_ratio: reviewed_objective,
              provider_ratio: listed_objective
            )
          end
          reviewed_seconds = duration_seconds(Support.fetch_value(intent, :evaluation_window).to_s)
          listed_seconds = duration_seconds(Support.fetch_value(listed, :period).to_s)
          unless reviewed_seconds == listed_seconds
            findings << Support.finding(
              'sloth_mcp_period_mismatch',
              'Sloth MCP period does not match reviewed evidence.',
              reviewed_seconds: reviewed_seconds,
              provider_seconds: listed_seconds
            )
          end
          detail_fields = %i[id sloth_id service_id objective period burning_budget_percent burned_budget_window_percent]
          mismatched = detail_fields.select do |field|
            left = Support.fetch_value(listed, field)
            right = Support.fetch_value(detailed, field)
            left.is_a?(Numeric) && right.is_a?(Numeric) ? !close?(left, right) : left != right
          end
          unless mismatched.empty?
            findings << Support.finding(
              'sloth_mcp_detail_mismatch',
              'Sloth MCP list and detail results disagree.',
              fields: mismatched.map(&:to_s)
            )
          end
          consumed = numeric_value(Support.fetch_value(listed, :burned_budget_window_percent))
          remaining = Support.fetch_value(budget, :current_remaining_percent)
          unless close?(100.0 - consumed, remaining)
            findings << Support.finding(
              'sloth_mcp_budget_mismatch',
              'Sloth MCP list and range budget values disagree.',
              list_consumed_percent: consumed,
              range_remaining_percent: remaining
            )
          end
          findings
        end

        def provider_slo_evidence(item)
          {
            slo_id: Support.fetch_value(item, :id),
            sloth_id: Support.fetch_value(item, :sloth_id),
            service_id: Support.fetch_value(item, :service_id),
            objective_percent: numeric_value(Support.fetch_value(item, :objective)),
            period: Support.fetch_value(item, :period),
            current_burn_percent: numeric_value(Support.fetch_value(item, :burning_budget_percent)),
            consumed_budget_percent: numeric_value(Support.fetch_value(item, :burned_budget_window_percent)),
            alerts: {
              page: Support.fetch_value(item, :has_page_alert) == true,
              warning: Support.fetch_value(item, :has_warning_alert) == true
            }
          }
        end

        def parse_budget_range(value, config)
          exact_keys!(
            value,
            %w[current_burned_value_percent current_expected_burned_value_percent start_ts step real_series perfect_series],
            'get_slo_burned_budget_range'
          )
          real_values = series(Support.fetch_value(value, :real_series), config, allow_missing: true)
          expected_values = series(Support.fetch_value(value, :perfect_series), config, allow_missing: false)
          unless real_values.length == expected_values.length
            contract_error!(
              'invalid_sloth_mcp_series',
              'Sloth MCP budget series must contain the same number of points.'
            )
          end
          {
            current_remaining_percent: bounded_percent(
              Support.fetch_value(value, :current_burned_value_percent),
              'current_burned_value_percent'
            ),
            expected_remaining_percent: bounded_percent(
              Support.fetch_value(value, :current_expected_burned_value_percent),
              'current_expected_burned_value_percent'
            ),
            start: timestamp(Support.fetch_value(value, :start_ts), 'burned budget start'),
            step_seconds: series_step(
              Support.fetch_value(value, :step),
              'burned budget step',
              point_count: real_values.length
            ),
            real_values: real_values,
            expected_values: expected_values
          }
        end

        def parse_availability_range(value, config)
          exact_keys!(
            value,
            %w[start_ts step availability_series],
            'get_slo_sli_availability_range'
          )
          values = series(Support.fetch_value(value, :availability_series), config, allow_missing: true)
          {
            from: config.from.iso8601,
            to: config.to.iso8601,
            start: timestamp(Support.fetch_value(value, :start_ts), 'availability start'),
            step_seconds: series_step(
              Support.fetch_value(value, :step),
              'availability step',
              point_count: values.length
            ),
            values: values
          }
        end

        def series(raw, config, allow_missing:)
          values = raw.to_s.split(',', -1)
          if values.empty? || values.length > config.max_series_points
            contract_error!(
              'invalid_sloth_mcp_series',
              'Sloth MCP compressed series is empty or exceeds the point limit.',
              max_series_points: config.max_series_points
            )
          end
          values.map do |value|
            if value == 'x' && allow_missing
              nil
            else
              number = numeric_value(value)
              contract_error!('invalid_sloth_mcp_series', 'Sloth MCP series contains a non-finite number.') unless number.finite?
              number
            end
          end
        rescue ContractError, ArgumentError, TypeError
          contract_error!('invalid_sloth_mcp_series', 'Sloth MCP compressed series is malformed.')
        end

        def validate_slo_item!(item, source:)
          unless item.is_a?(Hash)
            contract_error!('invalid_sloth_mcp_tool_result', 'Sloth MCP SLO item must be an object.', source: source)
          end
          unexpected = item.keys.map(&:to_s) - SLO_ITEM_KEYS
          required = %w[id sloth_id service_id objective period is_grouped burning_budget_percent burned_budget_window_percent has_page_alert has_warning_alert]
          missing = required.reject { |key| item.key?(key) || item.key?(key.to_sym) }
          unless unexpected.empty? && missing.empty?
            contract_error!(
              'invalid_sloth_mcp_tool_result',
              'Sloth MCP SLO item fields do not match the pinned schema.',
              source: source,
              missing: missing.sort,
              unexpected: unexpected.sort
            )
          end
          %i[id sloth_id service_id].each do |field|
            unless Support.fetch_value(item, field).to_s.match?(ID_PATTERN)
              contract_error!('invalid_sloth_mcp_identity', 'Sloth MCP returned an invalid identity.', field: field.to_s)
            end
          end
          bounded_percent(Support.fetch_value(item, :objective), 'objective', minimum_exclusive: 0.0)
          nonnegative_number(Support.fetch_value(item, :burning_budget_percent), 'burning_budget_percent')
          nonnegative_number(Support.fetch_value(item, :burned_budget_window_percent), 'burned_budget_window_percent')
          duration_seconds(Support.fetch_value(item, :period).to_s)
          %i[is_grouped has_page_alert has_warning_alert].each do |field|
            next if [true, false].include?(Support.fetch_value(item, field))

            contract_error!('invalid_sloth_mcp_tool_result', 'Sloth MCP boolean field is invalid.', field: field.to_s)
          end
        end

        def checked_tool_call(client, name, arguments)
          contract_error!('unsafe_sloth_mcp_tool', 'Attempted tool is outside the read-only allowlist.', tool: name) unless TOOL_CONTRACTS.key?(name)
          client.call_tool(name, arguments)
        end

        def exact_keys!(value, expected, source)
          unless value.is_a?(Hash) && value.keys.map(&:to_s).sort == expected.sort
            actual = value.is_a?(Hash) ? value.keys.map(&:to_s).sort : []
            contract_error!(
              'invalid_sloth_mcp_tool_result',
              'Sloth MCP tool result fields do not match the pinned schema.',
              source: source,
              expected: expected.sort,
              actual: actual
            )
          end
        end

        def identity_error!(findings)
          raise ContractError.new(
            'invalid_sloth_mcp_identity',
            'Sloth MCP identities do not exactly match reviewed downstream evidence.',
            findings: findings
          )
        end

        def contract_error!(code, message, details = {})
          raise ContractError.new(code, message, findings: [Support.finding(code, message, details)])
        end

        def duration_seconds(value)
          remaining = value.to_s
          total = 0.0
          units = { 'd' => 86_400, 'h' => 3_600, 'm' => 60, 's' => 1, 'ms' => 0.001 }
          until remaining.empty?
            match = remaining.match(/\A([0-9]+(?:\.[0-9]+)?)(ms|[dhms])/)
            contract_error!('invalid_sloth_mcp_duration', 'Sloth MCP duration is invalid.') unless match
            total += Float(match[1]) * units.fetch(match[2])
            remaining = remaining[match[0].length..]
          end
          contract_error!('invalid_sloth_mcp_duration', 'Sloth MCP duration must be positive.') unless total.positive?
          total
        rescue ArgumentError, TypeError
          contract_error!('invalid_sloth_mcp_duration', 'Sloth MCP duration is invalid.')
        end

        def positive_duration(value, name)
          duration_seconds(value.to_s)
        rescue ContractError
          contract_error!('invalid_sloth_mcp_series', "Sloth MCP #{name} is invalid.")
        end

        def series_step(value, name, point_count:)
          return 0.0 if value.to_s == '0s' && point_count == 1

          positive_duration(value, name)
        end

        def range_type(from, to)
          days = (to - from) / 86_400
          return 'weekly' if days <= 7
          return 'monthly' if days <= 31
          return 'quarterly' if days <= 92

          'yearly'
        end

        def timestamp(value, name)
          Time.iso8601(value.to_s).utc.iso8601
        rescue ArgumentError
          contract_error!('invalid_sloth_mcp_series', "Sloth MCP #{name} must be ISO 8601.")
        end

        def numeric_value(value)
          number = Float(value)
          contract_error!('invalid_sloth_mcp_number', 'Sloth MCP numeric value must be finite.') unless number.finite?
          number
        rescue ArgumentError, TypeError
          contract_error!('invalid_sloth_mcp_number', 'Sloth MCP numeric value is invalid.')
        end

        def integer_value(value)
          Integer(value)
        rescue ArgumentError, TypeError
          contract_error!('invalid_sloth_mcp_number', 'Sloth MCP integer value is invalid.')
        end

        def bounded_percent(value, name, minimum_exclusive: nil)
          number = numeric_value(value)
          valid = number >= 0.0 && number <= 100.0
          valid &&= number > minimum_exclusive if minimum_exclusive
          contract_error!('invalid_sloth_mcp_number', "Sloth MCP #{name} must be a valid percentage.") unless valid
          number
        end

        def nonnegative_number(value, name)
          number = numeric_value(value)
          contract_error!('invalid_sloth_mcp_number', "Sloth MCP #{name} must be nonnegative.") if number.negative?
          number
        end

        def close?(left, right)
          (Float(left) - Float(right)).abs <= NUMBER_TOLERANCE
        end

        def build_report(manifest, evidence, connection, config, results, findings)
          tools = Array(Support.fetch_value(connection, :tools))
          matched = results.count { |result| result.fetch(:status) == 'matched' }
          {
            schema_version: SCHEMA_VERSION,
            kind: KIND,
            provider: 'sloth',
            service: Support.fetch_value(evidence, :service),
            generated_at: @clock.call.utc.iso8601,
            source: {
              manifest_fingerprint: Support.fingerprint(manifest),
              evidence_id: Support.fetch_value(evidence, :evidence_id),
              evidence_fingerprint: Support.fingerprint(evidence)
            },
            runtime: {
              protocol_version: Support.fetch_value(connection, :protocol_version),
              server: {
                name: Support.fetch_value(Support.fetch_value(connection, :server_info, {}), :name),
                version: Support.fetch_value(Support.fetch_value(connection, :server_info, {}), :version)
              },
              capability: SUPPORTED_VERSIONS.fetch(config.expected_version),
              tools: tools.map { |tool| Support.fetch_value(tool, :name).to_s }.sort,
              tool_schema_fingerprint: Support.fingerprint(
                tools.map do |tool|
                  {
                    name: Support.fetch_value(tool, :name),
                    input_schema: Support.fetch_value(tool, :inputSchema),
                    output_schema: Support.fetch_value(tool, :outputSchema),
                    read_only: Support.fetch_value(Support.fetch_value(tool, :annotations, {}), :readOnlyHint)
                  }
                end.sort_by { |tool| tool.fetch(:name).to_s }
              )
            },
            request: {
              from: config.from.iso8601,
              to: config.to.iso8601,
              page_size: config.page_size,
              max_pages: config.max_pages,
              max_series_points: config.max_series_points,
              timeout_seconds: config.timeout_seconds,
              max_response_bytes: config.max_response_bytes
            },
            status: findings.empty? ? 'matched' : 'drift',
            authoritative_status_transport: false,
            summary: {
              expected_slos: results.length,
              matched_slos: matched,
              drifted_slos: results.length - matched,
              finding_count: findings.length
            },
            slos: results,
            findings: findings
          }
        end
      end
    end
  end
end
