# frozen_string_literal: true

module SloRulesEngine
  module Application
    class DiffProviderState
      FILE_PROVIDERS = %w[prometheus_stack sloth].freeze

      def initialize(definition_loader: DefinitionLoader.new, manifest_loader: ManifestLoader.new)
        @definition_loader = definition_loader
        @manifest_loader = manifest_loader
      end

      def call(arguments, context:)
        provider = context.provider_registry.fetch(arguments.fetch('provider'))
        output_dir = arguments['output_dir']
        if FILE_PROVIDERS.include?(provider.key) && output_dir.to_s.empty?
          raise CommandError.new(
            'missing_agent_argument',
            'file-backed provider diff requires output_dir',
            field: 'output_dir'
          )
        end
        manifest_path = arguments['manifest_file']
        definition_paths = arguments['definition_files']
        if manifest_path.to_s.empty? == Array(definition_paths).empty?
          raise CommandError.new(
            'ambiguous_agent_input',
            'diff requires exactly one of manifest_file or definition_files'
          )
        end

        context.input_policy.validate_lexical_paths!(
          input_paths(manifest_path, definition_paths, output_dir)
        )
        resolved_output = resolve_output_dir(output_dir, context)
        manifests_or_result = resolve_manifests(
          provider,
          manifest_path,
          definition_paths,
          context
        )
        return manifests_or_result if manifests_or_result.is_a?(CommandResult)

        applier = build_applier(provider, resolved_output)
        plans = manifests_or_result.map { |manifest| applier.diff(manifest).to_h }
        CommandResult.new(value: plans, side_effect: 'provider_read')
      end

      private

      def input_paths(manifest_path, definition_paths, output_dir)
        paths = []
        paths << { path: manifest_path, field: 'manifest_file', extensions: ['.json'] } if manifest_path
        Array(definition_paths).each do |path|
          paths << { path: path, field: 'definition_files', extensions: ['.rb'] }
        end
        paths << { path: output_dir, field: 'output_dir' } if output_dir
        paths
      end

      def resolve_output_dir(output_dir, context)
        return unless output_dir

        context.input_policy.resolve_read_root(
          output_dir,
          field: 'output_dir',
          prevalidated: true
        )
      end

      def build_applier(provider, output_dir)
        return SloRulesEngine::Appliers::Datadog.new if provider.key == 'datadog'

        SloRulesEngine::Appliers::ManifestBundle.new(output_dir: output_dir)
      end

      def resolve_manifests(provider, manifest_path, definition_paths, context)
        if manifest_path
          return @manifest_loader.load_file(
            manifest_path,
            provider: provider,
            context: context,
            prevalidated: true
          )
        end

        definitions = @definition_loader.load_files(definition_paths, context: context)
        validation = validate_for_provider(definitions, provider)
        unless validation[:valid]
          return CommandResult.new(
            value: validation,
            side_effect: 'provider_read',
            findings: validation[:errors] + validation[:warnings],
            exit_status: 1
          )
        end
        manifests = definitions.map do |definition|
          provider.generate(definition).to_h.merge(service: definition.service)
        end
        manifests.each { |manifest| SloRulesEngine::ManifestSchemaValidator.validate!(manifest) }
        manifests
      end

      def validate_for_provider(definitions, provider)
        core_validator = SloRulesEngine::CoreValidator.new
        errors = []
        warnings = []
        definitions.each do |definition|
          core_result = core_validator.validate(definition)
          provider_result = provider.validate(definition)
          errors.concat(core_result.errors.map(&:to_h))
          errors.concat(provider_result.errors.map(&:to_h))
          warnings.concat(core_result.warnings.map(&:to_h))
          warnings.concat(provider_result.warnings.map(&:to_h))
        end
        { valid: errors.empty?, errors: errors, warnings: warnings }
      end
    end
  end
end
