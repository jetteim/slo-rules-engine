# frozen_string_literal: true

require 'json'
require 'optparse'

module SloRulesEngine
  module CLI
    module AgentCommands
      def agent(argv)
        subcommand = argv.shift
        definition = command_registry.find_human(['agent', subcommand]) if subcommand
        unless definition
          code = subcommand ? 'unknown_agent_subcommand' : 'missing_agent_subcommand'
          return render_agent_contract_error(code, 'agent subcommand must be catalog or describe')
        end

        public_send(definition.handler, argv)
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

      def agent_argument_error(message)
        raise SloRulesEngine::CLI::AgentIntrospection::ContractError.new(
          'invalid_agent_arguments',
          message
        )
      end

      def render_agent_contract_error(code, message)
        render_agent_error(
          SloRulesEngine::CLI::AgentIntrospection::ContractError.new(code, message)
        )
      end

      def render_agent_error(error)
        puts JSON.pretty_generate(agent_introspection.error_payload(error))
        exit 1
      end
    end
  end
end
