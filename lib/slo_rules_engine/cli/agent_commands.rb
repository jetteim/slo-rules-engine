# frozen_string_literal: true

require 'json'
require 'optparse'
require_relative 'agent_invocation'

module SloRulesEngine
  module CLI
    module AgentCommands
      def agent(argv)
        subcommand = argv.shift
        return agent_invoke(argv) if subcommand == 'invoke'

        definition = command_registry.find_human(['agent', subcommand]) if subcommand
        unless definition
          code = subcommand ? 'unknown_agent_subcommand' : 'missing_agent_subcommand'
          return render_agent_contract_error(code, 'agent subcommand must be catalog, describe, or invoke')
        end

        public_send(definition.handler, argv)
      end

      def agent_invoke(argv)
        options = {}
        parser = OptionParser.new do |opts|
          opts.on('--json=JSON', 'Complete inline Agent command request') { |value| options[:json] = value }
          opts.on('--json-file=FILE', 'Read the complete Agent command request from FILE') { |value| options[:json_file] = value }
          opts.on('--stdin', 'Read the complete Agent command request from stdin') { options[:stdin] = true }
          opts.on('--format=FORMAT', 'Output format; json is currently supported') { |value| options[:format] = value }
        end
        parser.parse!(argv)
        command_id = argv.shift
        agent_argument_error('missing command ID') if command_id.to_s.empty?
        agent_argument_error('unexpected arguments') unless argv.empty?
        sources = %i[json json_file stdin].select { |name| options[name] }
        unless sources.length == 1
          raise SloRulesEngine::CLI::AgentIntrospection::ContractError.new(
            'invalid_agent_request_source',
            'use exactly one of --json, --json-file, or --stdin'
          )
        end

        format = options[:format] || ENV['RULES_CTL_OUTPUT_FORMAT'] || 'json'
        raw = if options[:json]
                options[:json]
              elsif options[:json_file]
                agent_invocation.read_request_file(options[:json_file])
              else
                agent_input.read
              end
        request = agent_invocation.parse_request(raw)
        payload = agent_invocation.invoke(command_id, request, format: format)
        puts JSON.pretty_generate(payload)
        exit payload.fetch(:exit_status) unless payload.fetch(:exit_status).zero?
      rescue OptionParser::ParseError => error
        render_agent_contract_error('invalid_agent_arguments', error.message, command_id: command_id)
      rescue SloRulesEngine::CLI::AgentIntrospection::ContractError => error
        render_agent_error(error, command_id: command_id)
      end

      def agent_catalog(argv)
        options = { format: 'json', limit: SloRulesEngine::CLI::AgentIntrospection::DEFAULT_LIMIT }
        parser = OptionParser.new do |opts|
          opts.on('--format=FORMAT', 'Output format; only json is supported') { |value| options[:format] = value }
          opts.on('--limit=N', Integer, 'Maximum commands to return') { |value| options[:limit] = value }
          opts.on('--cursor=COMMAND_ID', 'Continue after this command ID') { |value| options[:cursor] = value }
        end
        parser.parse!(argv)
        agent_argument_error('unexpected arguments') unless argv.empty?
        agent_argument_error('only --format=json is supported') unless options[:format] == 'json'

        puts JSON.pretty_generate(agent_introspection.catalog(limit: options[:limit], cursor: options[:cursor]))
      rescue OptionParser::ParseError => error
        render_agent_contract_error('invalid_agent_arguments', error.message)
      rescue SloRulesEngine::CLI::AgentIntrospection::ContractError => error
        render_agent_error(error)
      end

      def agent_describe(argv)
        options = { format: 'json' }
        parser = OptionParser.new do |opts|
          opts.on('--format=FORMAT', 'Output format; only json is supported') { |value| options[:format] = value }
        end
        parser.parse!(argv)
        command_id = argv.shift
        agent_argument_error('missing command ID') if command_id.to_s.empty?
        agent_argument_error('unexpected arguments') unless argv.empty?
        agent_argument_error('only --format=json is supported') unless options[:format] == 'json'

        puts JSON.pretty_generate(agent_introspection.describe(command_id))
      rescue OptionParser::ParseError => error
        render_agent_contract_error('invalid_agent_arguments', error.message)
      rescue SloRulesEngine::CLI::AgentIntrospection::ContractError => error
        render_agent_error(error)
      end

      def agent_introspection
        SloRulesEngine::CLI::AgentIntrospection.new(command_registry)
      end

      def agent_invocation
        SloRulesEngine::CLI::AgentInvocation.new(
          registry: command_registry,
          application_context: agent_application_context
        )
      end

      def agent_input
        $stdin
      end

      def agent_argument_error(message)
        raise SloRulesEngine::CLI::AgentIntrospection::ContractError.new(
          'invalid_agent_arguments',
          message
        )
      end

      def render_agent_contract_error(code, message, command_id: nil)
        render_agent_error(
          SloRulesEngine::CLI::AgentIntrospection::ContractError.new(code, message),
          command_id: command_id
        )
      end

      def render_agent_error(error, command_id: nil)
        definition = command_registry.fetch(command_id) if command_id
        puts JSON.pretty_generate(
          agent_introspection.error_payload(error, command_id: command_id, definition: definition)
        )
        exit 1
      rescue KeyError
        puts JSON.pretty_generate(agent_introspection.error_payload(error, command_id: command_id))
        exit 1
      end
    end
  end
end
