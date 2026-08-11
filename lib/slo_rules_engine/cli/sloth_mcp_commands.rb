# frozen_string_literal: true

require 'json'
require 'optparse'

module SloRulesEngine
  module CLI
    module SlothMcpCommands
      def sloth_mcp(argv)
        dispatch_registered_subcommand(
          'sloth-mcp',
          argv,
          'usage: sloth-mcp compare'
        )
      end

      def sloth_mcp_compare(argv)
        options = {
          allowed_hosts: [],
          page_size: 100,
          max_pages: 10,
          max_series_points: 1_000,
          timeout_seconds: 10,
          max_response_bytes: 1_048_576
        }
        parser = OptionParser.new do |opts|
          opts.on('--manifest=FILE', 'Reviewed Sloth provider manifest') { |value| options[:manifest_path] = value }
          opts.on('--evidence=FILE', 'Current downstream Sloth evidence') { |value| options[:evidence_path] = value }
          opts.on('--endpoint=URL', 'Sloth Streamable HTTP MCP endpoint') { |value| options[:endpoint] = value }
          opts.on('--allow-host=HOST', 'Allowed Sloth MCP host; repeat when needed') do |value|
            options[:allowed_hosts] << value
          end
          opts.on('--expected-version=VERSION', 'Exact tested Sloth MCP runtime version') do |value|
            options[:expected_version] = value
          end
          opts.on('--from=TIMESTAMP', 'Comparison range start in ISO 8601') { |value| options[:from] = value }
          opts.on('--to=TIMESTAMP', 'Comparison range end in ISO 8601') { |value| options[:to] = value }
          opts.on('--page-size=N', Integer, 'Maximum items requested per page') { |value| options[:page_size] = value }
          opts.on('--max-pages=N', Integer, 'Maximum pages per list tool') { |value| options[:max_pages] = value }
          opts.on('--max-series-points=N', Integer, 'Maximum compressed series points') do |value|
            options[:max_series_points] = value
          end
          opts.on('--timeout-seconds=N', Integer, 'Per-request timeout') { |value| options[:timeout_seconds] = value }
          opts.on('--max-response-bytes=N', Integer, 'Maximum response bytes') do |value|
            options[:max_response_bytes] = value
          end
          opts.on('--output=FILE', 'Write the comparison report') { |value| options[:output_path] = value }
        end
        parser.parse!(argv)
        %i[manifest_path evidence_path endpoint expected_version from to output_path].each do |key|
          abort_usage("missing --#{key.to_s.sub('_path', '').tr('_', '-')}") if options[key].to_s.empty?
        end
        abort_usage('missing --allow-host') if options[:allowed_hosts].empty?
        abort_usage('unexpected arguments') unless argv.empty?

        output_path = options.delete(:output_path)
        report = sloth_mcp_comparison.compare(**options)
        write_json_file(output_path, report)
        puts JSON.pretty_generate(report)
        exit 1 unless report.fetch(:status) == 'matched'
      rescue SloRulesEngine::Sloth::Mcp::ContractError => error
        puts JSON.pretty_generate(
          valid: false,
          provider: 'sloth',
          mode: 'sloth_mcp_compare',
          error: {
            code: error.code,
            message: error.message
          },
          findings: error.findings
        )
        exit 1
      end

      def sloth_mcp_comparison
        SloRulesEngine::Sloth::Mcp::Comparison.new
      end
    end
  end
end
