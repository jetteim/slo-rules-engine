# frozen_string_literal: true

require 'json'

module SloRulesEngine
  module Application
    class DefinitionLoader
      def load_files(paths, context:)
        resolved_paths = context.input_policy.resolve_read_files(
          paths,
          field: 'definition_files',
          extensions: ['.rb']
        )
        SloRulesEngine.clear_definitions
        resolved_paths.each { |path| load path }
        SloRulesEngine.definitions
      rescue InputSafety::Error
        raise
      rescue SystemExit, ScriptError, StandardError => error
        raise CommandError.new(
          'definition_load_failed',
          'definition file could not be loaded safely',
          error_class: error.class.name
        )
      end
    end

    class ManifestLoader
      def load_file(path, provider:, context:, prevalidated: false)
        load_files(
          [path],
          provider: provider,
          context: context,
          field: 'manifest_file',
          prevalidated: prevalidated
        )
      end

      def load_files(paths, provider:, context:, field: 'manifest_files', prevalidated: false)
        resolved_paths = context.input_policy.resolve_read_files(
          paths,
          field: field,
          extensions: ['.json'],
          prevalidated: prevalidated
        )
        manifests = resolved_paths.flat_map do |resolved_path|
          payload = JSON.parse(File.read(resolved_path), symbolize_names: true)
          payload.is_a?(Array) ? payload : [payload]
        end
        manifests.each do |manifest|
          manifest_provider = manifest.fetch(:provider) { manifest.fetch('provider', nil) }
          unless manifest_provider == provider.key
            raise CommandError.new(
              'manifest_provider_mismatch',
              'manifest provider does not match the requested provider',
              expected_provider: provider.key,
              actual_provider: manifest_provider
            )
          end
          SloRulesEngine::ManifestSchemaValidator.validate!(manifest)
        end
        manifests
      rescue JSON::ParserError
        raise CommandError.new(
          'invalid_agent_input_file',
          'manifest input is not valid JSON',
          field: field
        )
      end
    end
  end
end
