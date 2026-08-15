# frozen_string_literal: true

require 'json'

module SloRulesEngine
  module CLI
    module ReportCommands
      def migration_report(argv)
        abort_usage('missing file') if argv.empty?

        result = SloRulesEngine::Application::BuildMigrationReport.new.call(
          { 'legacy_files' => argv },
          context: application_context
        )
        puts JSON.pretty_generate(result.value)
        exit result.exit_status unless result.exit_status.zero?
      end

      def model_report(argv)
        abort_usage('missing definition file') if argv.empty?

        result = SloRulesEngine::Application::BuildModelReport.new.call(
          { 'definition_files' => argv },
          context: application_context
        )
        puts JSON.pretty_generate(result.value)
      end
    end
  end
end
