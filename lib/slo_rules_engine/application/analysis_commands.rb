# frozen_string_literal: true

module SloRulesEngine
  module Application
    class RecommendCalculationBasis
      def call(arguments, context:)
        recommendation = SloRulesEngine::RealityCheck::CalculationBasisAdvisor.new.recommend(
          observations_per_second: arguments.fetch('observations_per_second'),
          failed_observations_to_alert: arguments.fetch('failed_observations_to_alert')
        )
        CommandResult.new(value: recommendation.to_h)
      end
    end

    class ValidateDefinitions
      def initialize(loader: DefinitionLoader.new)
        @loader = loader
      end

      def call(arguments, context:)
        definitions = @loader.load_files(arguments.fetch('definition_files'), context: context)
        validator = SloRulesEngine::CoreValidator.new
        results = definitions.map do |definition|
          validator.validate(definition).to_h.merge(service: definition.service)
        end
        valid = results.all? { |result| result[:valid] }
        findings = results.flat_map { |result| result[:errors] + result[:warnings] }
        CommandResult.new(
          value: results,
          side_effect: 'local_read',
          findings: findings,
          exit_status: valid ? 0 : 1
        )
      end
    end

    class BuildMigrationReport
      def call(arguments, context:)
        input_paths = arguments.fetch('legacy_files')
        resolved_paths = context.input_policy.resolve_read_files(
          input_paths,
          field: 'legacy_files',
          extensions: ['.rb']
        )
        display_paths = resolved_paths.zip(input_paths).to_h
        report = SloRulesEngine::MigrationReport.scan_files(resolved_paths)
        value = report.to_h
        value[:findings] = value.fetch(:findings).map do |finding|
          finding.merge(file: display_paths.fetch(finding.fetch(:file), finding.fetch(:file)))
        end
        CommandResult.new(
          value: value,
          side_effect: 'local_read',
          findings: value.fetch(:findings),
          exit_status: report.valid? ? 0 : 1
        )
      end
    end

    class BuildModelReport
      def initialize(loader: DefinitionLoader.new)
        @loader = loader
      end

      def call(arguments, context:)
        definitions = @loader.load_files(arguments.fetch('definition_files'), context: context)
        report = SloRulesEngine::ReliabilityModel::ReportBuilder.new.build(definitions)
        CommandResult.new(value: report, side_effect: 'local_read')
      end
    end
  end
end
