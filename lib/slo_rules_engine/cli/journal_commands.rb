# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'optparse'
require 'tempfile'

module SloRulesEngine
  module CLI
    module JournalCommands
      def journal(argv)
        subcommand = argv.shift
        case subcommand
        when 'create'
          journal_create(argv)
        when 'status'
          journal_status(argv)
        else
          abort_usage('usage: journal create|status')
        end
      end

      def journal_create(argv)
        input_path = argv.shift
        output_path = nil
        parser = OptionParser.new do |opts|
          opts.on('--output=FILE', 'Write the immutable initial operation journal to FILE') do |value|
            output_path = value
          end
        end
        parser.parse!(argv)
        abort_usage('missing provider plan path') if input_path.to_s.empty?
        abort_usage('missing --output') if output_path.to_s.empty?
        abort_usage('unexpected arguments') unless argv.empty?

        saved_plan = JSON.parse(File.read(input_path), symbolize_names: true)
        plan = ProviderState::PlanLoader.new.load(saved_plan)
        operation_journal = ProviderState::JournalBuilder.new.build(plan).to_h
        persist_initial_journal(output_path, operation_journal)
        puts JSON.pretty_generate(operation_journal)
      rescue ProviderState::ContractError => error
        render_journal_error(
          code: 'invalid_provider_plan',
          message: error.message,
          errors: [{ path: error.path, message: error.message }]
        )
      rescue Errno::ENOENT, Errno::EACCES, JSON::ParserError => error
        render_journal_error(code: 'invalid_journal_input', message: error.message)
      end

      def journal_status(argv)
        path = argv.shift
        abort_usage('missing operation journal path') if path.to_s.empty?
        abort_usage('unexpected arguments') unless argv.empty?

        operation_journal = JSON.parse(File.read(path), symbolize_names: true)
        status = ProviderState::JournalEvaluator.new.evaluate(operation_journal)
        puts JSON.pretty_generate(status)
        exit 1 unless status.fetch(:valid)
      rescue Errno::ENOENT, Errno::EACCES, JSON::ParserError => error
        render_journal_error(code: 'invalid_journal_input', message: error.message)
      end

      private

      def persist_initial_journal(path, payload)
        if File.exist?(path)
          existing = begin
            JSON.parse(File.read(path), symbolize_names: true)
          rescue JSON::ParserError
            nil
          end
          return if existing == payload

          render_journal_error(
            code: 'journal_output_conflict',
            message: 'operation journal output already exists with different content'
          )
        end

        directory = File.dirname(path)
        FileUtils.mkdir_p(directory)
        Tempfile.create(['.operation-journal-', '.tmp'], directory) do |file|
          file.write(JSON.pretty_generate(payload))
          file.write("\n")
          file.flush
          file.fsync
          file.close
          File.rename(file.path, path)
        end
      end

      def render_journal_error(code:, message:, errors: nil)
        puts JSON.pretty_generate(
          {
            valid: false,
            error: {
              code: code,
              message: message
            },
            errors: errors
          }.compact
        )
        exit 1
      end
    end
  end
end
