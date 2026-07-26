# frozen_string_literal: true

require 'json'
require 'optparse'

module SloRulesEngine
  module CLI
    module BundleCommands
      def bundle(argv)
        subcommand = argv.shift
        case subcommand
        when 'create'
          bundle_create(argv)
        when 'plan'
          bundle_plan(argv)
        when 'status'
          bundle_status(argv)
        else
          abort_usage('usage: bundle create|plan|status')
        end
      end

      def bundle_create(argv)
        artifact_index_path = nil
        reviewer = nil
        reviewed_at = nil
        output_path = nil
        plans = {}
        parser = OptionParser.new do |opts|
          opts.on('--artifact-index=FILE', 'Saved onboarding artifact index to package') do |value|
            artifact_index_path = value
          end
          opts.on('--reviewer=IDENTITY', 'Reviewer identity attesting bundle assembly') { |value| reviewer = value }
          opts.on('--reviewed-at=TIMESTAMP', 'Explicit ISO 8601 review timestamp') { |value| reviewed_at = value }
          opts.on('--plan=TARGET=FILE', 'Dry-run plan for service/provider target; repeatable') do |value|
            target, path = value.split('=', 2)
            abort_usage('invalid --plan; expected service/provider=FILE') if target.to_s.empty? || path.to_s.empty?
            abort_usage("duplicate --plan target #{target.inspect}") if plans.key?(target)

            plans[target] = path
          end
          opts.on('--output=FILE', 'Write the release bundle to FILE') { |value| output_path = value }
        end
        parser.parse!(argv)
        abort_usage('missing --artifact-index') if artifact_index_path.to_s.empty?
        abort_usage('missing --reviewer') if reviewer.to_s.empty?
        abort_usage('missing --reviewed-at') if reviewed_at.to_s.empty?
        abort_usage('missing --output') if output_path.to_s.empty?
        abort_usage('unexpected arguments') unless argv.empty?

        release_bundle = SloRulesEngine::ReleaseBundle::Builder.new.build(
          artifact_index_path,
          reviewer: reviewer,
          reviewed_at: reviewed_at,
          plans: plans
        )
        status = SloRulesEngine::ReleaseBundle::StatusEvaluator.new.evaluate(release_bundle)
        unless status[:valid]
          code = status[:effective_lifecycle] == 'stale' ? 'stale_bundle_inputs' : 'incomplete_bundle_inputs'
          render_bundle_error(
            code: code,
            message: 'release bundle inputs are not ready for a persisted bundle',
            status: status
          )
        end

        write_json_file(output_path, release_bundle)
        puts JSON.pretty_generate(release_bundle)
      rescue SloRulesEngine::ReleaseBundle::CredentialError => error
        render_bundle_error(
          code: 'credential_material_forbidden',
          message: error.message,
          errors: error.paths.map { |path| { path: path, message: 'credential-like keys are forbidden' } }
        )
      rescue SloRulesEngine::ReleaseBundle::SchemaError => error
        render_bundle_error(
          code: 'invalid_release_bundle',
          message: error.message,
          errors: error.result.errors.map(&:to_h)
        )
      rescue ArgumentError, Errno::ENOENT, Errno::EACCES, JSON::ParserError => error
        render_bundle_error(code: 'invalid_bundle_input', message: error.message)
      end

      def bundle_plan(argv)
        input_path = argv.shift
        output_path = nil
        target_runtime = {}
        parser = OptionParser.new do |opts|
          opts.on('--target-output=TARGET=DIR', 'Managed output directory for one file-backed target; repeatable') do |value|
            target, path = value.split('=', 2)
            abort_usage('invalid --target-output; expected service/provider=DIR') if target.to_s.empty? || path.to_s.empty?
            abort_usage("duplicate target runtime #{target.inspect}") if target_runtime.key?(target)

            target_runtime[target] = { output_dir: path }
          end
          opts.on('--target-backend=TARGET=MODE', 'Backend runtime for one API target; MODE must be environment') do |value|
            target, mode = value.split('=', 2)
            abort_usage('invalid --target-backend; expected service/provider=environment') if target.to_s.empty? || mode.to_s.empty?
            abort_usage("duplicate target runtime #{target.inspect}") if target_runtime.key?(target)

            target_runtime[target] = { backend: mode }
          end
          opts.on('--output=FILE', 'Write the planned release bundle to FILE') { |value| output_path = value }
        end
        parser.parse!(argv)
        abort_usage('missing release bundle path') if input_path.to_s.empty?
        abort_usage('missing --output') if output_path.to_s.empty?
        abort_usage('unexpected arguments') unless argv.empty?
        if File.expand_path(input_path) == File.expand_path(output_path)
          render_bundle_error(
            code: 'immutable_bundle_input',
            message: 'bundle plan output must differ from the predecessor bundle path'
          )
        end

        release_bundle = JSON.parse(File.read(input_path), symbolize_names: true)
        planned = SloRulesEngine::ReleaseBundle::Planner.new.plan(
          release_bundle,
          target_runtime: target_runtime
        )
        write_json_file(output_path, planned)
        puts JSON.pretty_generate(planned)
      rescue SloRulesEngine::ReleaseBundle::PlannerError => error
        render_bundle_error(code: error.code, message: error.message, findings: error.findings)
      rescue SloRulesEngine::ReleaseBundle::CredentialError => error
        render_bundle_error(
          code: 'credential_material_forbidden',
          message: error.message,
          errors: error.paths.map { |path| { path: path, message: 'credential-like keys are forbidden' } }
        )
      rescue SloRulesEngine::ReleaseBundle::SchemaError => error
        render_bundle_error(
          code: 'invalid_release_bundle',
          message: error.message,
          errors: error.result.errors.map(&:to_h)
        )
      rescue SloRulesEngine::Datadog::MissingCredentials => error
        render_bundle_error(code: 'missing_credentials', message: error.message)
      rescue SloRulesEngine::ManifestSchemaError => error
        render_bundle_error(
          code: 'invalid_provider_manifest',
          message: error.message,
          errors: error.result.errors.map(&:to_h)
        )
      rescue ArgumentError, Errno::ENOENT, Errno::EACCES, JSON::ParserError => error
        render_bundle_error(code: 'invalid_bundle_input', message: error.message)
      end

      def bundle_status(argv)
        path = argv.shift
        abort_usage('missing release bundle path') if path.to_s.empty?
        abort_usage('unexpected arguments') unless argv.empty?

        release_bundle = JSON.parse(File.read(path), symbolize_names: true)
        status = SloRulesEngine::ReleaseBundle::StatusEvaluator.new.evaluate(release_bundle)
        puts JSON.pretty_generate(status)
        exit 1 unless status[:valid]
      rescue Errno::ENOENT, Errno::EACCES, JSON::ParserError => error
        render_bundle_error(code: 'invalid_bundle_input', message: error.message)
      end

      def render_bundle_error(code:, message:, status: nil, findings: nil, errors: nil)
        payload = {
          valid: false,
          error: {
            code: code,
            message: message
          },
          bundle_id: status&.fetch(:bundle_id, nil),
          lifecycle: status&.fetch(:effective_lifecycle, nil),
          summary: status&.fetch(:summary, nil),
          findings: findings || status&.fetch(:findings, nil),
          errors: errors
        }.compact
        puts JSON.pretty_generate(payload)
        exit 1
      end
    end
  end
end
