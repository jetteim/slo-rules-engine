# frozen_string_literal: true

require 'json'

module SloRulesEngine
  module CLI
    module ReportCommands
      def migration_report(argv)
        abort_usage('missing file') if argv.empty?

        report = SloRulesEngine::MigrationReport.scan_files(argv)
        puts JSON.pretty_generate(report.to_h)
        exit(report.valid? ? 0 : 1)
      end

      def model_report(argv)
        definitions = load_definitions(argv)
        puts JSON.pretty_generate(SloRulesEngine::ReliabilityModel::ReportBuilder.new.build(definitions))
      end
    end
  end
end
