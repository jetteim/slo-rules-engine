# frozen_string_literal: true

require 'fileutils'
require 'json'

module SloRulesEngine
  module Application
    class LocalArtifactWriter
      def write_provider_manifests(output_dir, manifests, provider:, handoff_dir:, path_policy:,
                                   report_path_root: output_dir)
        destinations = manifests.map do |manifest|
          segments = [manifest.fetch(:service), manifest.fetch(:provider), 'manifest.json']
          {
            manifest: manifest,
            path: path_policy.resolve_write_child(output_dir, segments, field: 'generated_artifacts'),
            display_path: File.join(report_path_root, *segments)
          }
        end
        report_segments = ['manifest-review', "#{provider.key}.json"]
        report_path = path_policy.resolve_write_child(output_dir, report_segments, field: 'generated_artifacts')

        artifacts = destinations.map do |destination|
          write_json(destination.fetch(:path), destination.fetch(:manifest))
          { kind: 'provider_manifest', path: destination.fetch(:display_path) }
        end

        report = SloRulesEngine::ManifestReviewQueue::ReportBuilder.new.build(
          manifests,
          provider: provider.key,
          handoff_dir: handoff_dir
        )
        report[:report] = { path: File.join(report_path_root, *report_segments) }
        write_json(report_path, report)
        artifacts << { kind: 'manifest_review_report', path: report.dig(:report, :path) }
        artifacts
      end

      def write_json(path, payload)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(payload))
      end
    end

    module ProviderGenerationSupport
      private

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

      def generate_manifests(definitions, provider)
        definitions.map do |definition|
          provider.generate(definition).to_h.merge(service: definition.service)
        end.tap do |manifests|
          manifests.each { |manifest| SloRulesEngine::ManifestSchemaValidator.validate!(manifest) }
        end
      end

      def validation_only_result(command_id, provider, inputs:, output:)
        CommandResult.new(
          value: {
            valid: true,
            mode: 'validate_only',
            command_id: command_id,
            provider: provider.key,
            inputs: inputs,
            output: output,
            io: {
              local_reads: false,
              local_writes: false,
              provider_calls: false,
              credential_loading: false
            }
          },
          side_effect: 'none'
        )
      end

      def effective_read_root(path, field, context)
        return unless path

        resolved = context.input_policy.resolve_read_root(path, field: field, prevalidated: true)
        context.input_policy.confined? ? resolved : path
      end
    end

    class GenerateProviderManifests
      include ProviderGenerationSupport

      def initialize(loader: DefinitionLoader.new, writer: LocalArtifactWriter.new)
        @loader = loader
        @writer = writer
      end

      def call(arguments, context:)
        provider = context.provider_registry.fetch(arguments.fetch('provider'))
        definition_files = Array(arguments['definition_files'])
        if definition_files.empty?
          raise CommandError.new('missing_agent_argument', 'generate requires definition_files', field: 'definition_files')
        end

        output_dir = arguments['output_dir']
        handoff_dir = arguments['handoff_dir']
        context.input_policy.validate_lexical_paths!(
          definition_files.map { |path| { path: path, field: 'definition_files', extensions: ['.rb'] } } +
          [
            output_dir && { path: output_dir, field: 'output_dir', access: :write },
            handoff_dir && { path: handoff_dir, field: 'handoff_dir' }
          ]
        )

        if arguments['validate_only'] == true
          return validation_only_result(
            'generate',
            provider,
            inputs: { definition_file_count: definition_files.length, handoff_dir: !handoff_dir.nil? },
            output: { field: 'output_dir', path: output_dir, required_for_agent_execution: true }.compact
          )
        end

        resolved_output = if output_dir
                            context.input_policy.resolve_write_root(
                              output_dir,
                              field: 'output_dir',
                              prevalidated: true
                            )
                          end
        resolved_handoff = effective_read_root(handoff_dir, 'handoff_dir', context)
        definitions = @loader.load_files(definition_files, context: context)
        validation = validate_for_provider(definitions, provider)
        return CommandResult.new(value: validation, side_effect: 'local_write', findings: validation[:errors] + validation[:warnings], exit_status: 1) unless validation[:valid]

        manifests = generate_manifests(definitions, provider)
        artifacts = if resolved_output
                      @writer.write_provider_manifests(
                        resolved_output,
                        manifests,
                        provider: provider,
                        handoff_dir: resolved_handoff,
                        path_policy: context.input_policy,
                        report_path_root: output_dir
                      )
                    else
                      []
                    end
        CommandResult.new(value: manifests, side_effect: 'local_write', artifacts: artifacts)
      end
    end

    class ReviewProviderManifests
      include ProviderGenerationSupport

      def initialize(definition_loader: DefinitionLoader.new, manifest_loader: ManifestLoader.new,
                     writer: LocalArtifactWriter.new)
        @definition_loader = definition_loader
        @manifest_loader = manifest_loader
        @writer = writer
      end

      def call(arguments, context:)
        provider = context.provider_registry.fetch(arguments.fetch('provider'))
        definition_files = Array(arguments['definition_files'])
        manifest_files = Array(arguments['manifest_files'])
        unless definition_files.empty? ^ manifest_files.empty?
          raise CommandError.new(
            'ambiguous_agent_input',
            'manifest-review requires exactly one of definition_files or manifest_files'
          )
        end

        output_file = arguments['output_file']
        handoff_dir = arguments['handoff_dir']
        report_file = arguments['report_file']
        context.input_policy.validate_lexical_paths!(
          definition_files.map { |path| { path: path, field: 'definition_files', extensions: ['.rb'] } } +
          manifest_files.map { |path| { path: path, field: 'manifest_files', extensions: ['.json'] } } +
          [
            output_file && { path: output_file, field: 'output_file', extensions: ['.json'], access: :write },
            handoff_dir && { path: handoff_dir, field: 'handoff_dir' },
            report_file && { path: report_file, field: 'report_file', extensions: ['.json'] }
          ]
        )

        if arguments['validate_only'] == true
          return validation_only_result(
            'manifest-review',
            provider,
            inputs: {
              definition_file_count: definition_files.length,
              manifest_file_count: manifest_files.length,
              handoff_dir: !handoff_dir.nil?,
              saved_report: !report_file.nil?
            },
            output: { field: 'output_file', path: output_file, required_for_agent_execution: true }.compact
          )
        end

        resolved_output = if output_file
                            context.input_policy.resolve_write_file(
                              output_file,
                              field: 'output_file',
                              extensions: ['.json'],
                              prevalidated: true
                            )
                          end
        resolved_handoff = effective_read_root(handoff_dir, 'handoff_dir', context)
        manifests = if manifest_files.empty?
                      definitions = @definition_loader.load_files(definition_files, context: context)
                      validation = validate_for_provider(definitions, provider)
                      return CommandResult.new(value: validation, side_effect: 'local_write', findings: validation[:errors] + validation[:warnings], exit_status: 1) unless validation[:valid]

                      generate_manifests(definitions, provider)
                    else
                      @manifest_loader.load_files(manifest_files, provider: provider, context: context, field: 'manifest_files')
                    end
        report = SloRulesEngine::ManifestReviewQueue::ReportBuilder.new.build(
          manifests,
          provider: provider.key,
          handoff_dir: resolved_handoff
        )
        report[:report] = { path: output_file } if output_file
        if report_file
          saved = load_saved_report(report_file, context)
          report[:saved_report] = SloRulesEngine::ManifestReviewQueue::FreshnessValidator.new.validate(
            saved,
            report,
            path: report_file
          )
        end
        @writer.write_json(resolved_output, report) if resolved_output
        exit_status = report[:valid] && (!report[:saved_report] || report.dig(:saved_report, :fresh)) ? 0 : 1
        findings = report.fetch(:manifests).flat_map { |entry| entry.fetch(:findings) }
        findings.concat(report.dig(:saved_report, :findings) || [])
        artifacts = output_file ? [{ kind: 'manifest_review_report', path: output_file }] : []
        CommandResult.new(
          value: report,
          side_effect: 'local_write',
          findings: findings,
          artifacts: artifacts,
          exit_status: exit_status
        )
      end

      private

      def load_saved_report(path, context)
        resolved = context.input_policy.resolve_read_file(path, field: 'report_file', extensions: ['.json'], prevalidated: true)
        JSON.parse(File.read(resolved), symbolize_names: true)
      rescue JSON::ParserError
        raise CommandError.new(
          'invalid_agent_input_file',
          'saved manifest-review report is not valid JSON',
          field: 'report_file'
        )
      end
    end
  end
end
