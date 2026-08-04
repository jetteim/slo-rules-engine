# frozen_string_literal: true

require 'json'
require 'optparse'

module SloRulesEngine
  module CLI
    module BundleCommands
      def bundle(argv)
        dispatch_registered_subcommand(
          'bundle',
          argv,
          'usage: bundle create|plan|apply|verify|status'
        )
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

      def bundle_apply(argv)
        input_path = argv.shift
        confirm = false
        journal_dir = nil
        output_path = nil
        approved_plan_paths = []
        parser = OptionParser.new do |opts|
          opts.on('--confirm', 'Execute every covered file-backed target exactly') { confirm = true }
          opts.on('--approved-plan=FILE', 'Approved provider plan; repeat once per bundle target') do |value|
            approved_plan_paths << value
          end
          opts.on('--journal-dir=DIR', 'Durable exact-plan operation journal directory') do |value|
            journal_dir = value
          end
          opts.on('--output=FILE', 'Write the immutable applied release bundle') { |value| output_path = value }
        end
        parser.parse!(argv)
        abort_usage('missing apply-ready release bundle path') if input_path.to_s.empty?
        abort_usage('bundle apply requires --confirm') unless confirm
        abort_usage('bundle apply requires at least one --approved-plan') if approved_plan_paths.empty?
        abort_usage('bundle apply requires --journal-dir') if journal_dir.to_s.empty?
        abort_usage('bundle apply requires --output') if output_path.to_s.empty?
        abort_usage('unexpected arguments') unless argv.empty?
        if File.expand_path(input_path) == File.expand_path(output_path)
          render_bundle_error(
            code: 'immutable_bundle_input',
            message: 'bundle apply output must differ from the predecessor bundle path'
          )
        end

        release_bundle = JSON.parse(File.read(input_path), symbolize_names: true)
        approved_plans = approved_plan_paths.map do |path|
          payload = JSON.parse(File.read(path), symbolize_names: true)
          ProviderState::ApprovedPlan::Loader.new.load(payload)
        end
        store = SloRulesEngine::ReleaseBundle::Store.new
        store.preflight(
          output_path,
          predecessor_bundle_id: release_bundle.fetch(:bundle_id),
          approved_plan_ids: approved_plans.map(&:approved_plan_id)
        )
        executor = ProviderState::ExactPlanExecutor.new(journal_dir: journal_dir)
        applied = SloRulesEngine::ReleaseBundle::Applier.new(executor: executor).apply(
          release_bundle,
          approved_plans: approved_plans
        )
        store.write(output_path, applied)
        puts JSON.pretty_generate(applied)
      rescue SloRulesEngine::ReleaseBundle::ApplyError => error
        render_bundle_error(
          code: error.code,
          message: error.message,
          findings: error.findings,
          target_uid: error.target_uid,
          completed_targets: error.completed_targets,
          path: error.path
        )
      rescue SloRulesEngine::ProviderState::ApprovedPlan::Error => error
        render_bundle_error(
          code: error.code,
          message: error.message,
          findings: error.findings,
          path: error.path
        )
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

      def bundle_verify(argv)
        input_path = argv.shift
        output_path = nil
        parser = OptionParser.new do |opts|
          opts.on('--output=FILE', 'Write the immutable verified release bundle') do |value|
            output_path = value
          end
        end
        parser.parse!(argv)
        abort_usage('missing applied release bundle path') if input_path.to_s.empty?
        abort_usage('bundle verify requires --output') if output_path.to_s.empty?
        abort_usage('unexpected arguments') unless argv.empty?
        if File.expand_path(input_path) == File.expand_path(output_path)
          render_bundle_error(
            code: 'immutable_bundle_input',
            message: 'bundle verify output must differ from the predecessor bundle path'
          )
        end

        release_bundle = JSON.parse(File.read(input_path), symbolize_names: true)
        store = SloRulesEngine::ReleaseBundle::Store.new
        existing = store.preflight_verified(
          output_path,
          predecessor_bundle_id: release_bundle.fetch(:bundle_id)
        )
        checked_at = existing && Array(existing[:artifacts]).filter_map do |artifact|
          next unless ProviderState::Value.fetch(artifact, :kind) == 'target_verification'

          ProviderState::Value.fetch(ProviderState::Value.fetch(artifact, :content), :checked_at)
        end.min
        verified = SloRulesEngine::ReleaseBundle::Verifier.new.verify(
          release_bundle,
          checked_at: checked_at
        )
        store.write(output_path, verified)
        puts JSON.pretty_generate(verified)
      rescue SloRulesEngine::ReleaseBundle::VerifyError => error
        render_bundle_error(
          code: error.code,
          message: error.message,
          findings: error.findings,
          target_uid: error.target_uid,
          path: error.path
        )
      rescue SloRulesEngine::ReleaseBundle::ApplyError => error
        render_bundle_error(
          code: error.code,
          message: error.message,
          findings: error.findings,
          path: error.path
        )
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
      rescue ArgumentError, KeyError, Errno::ENOENT, Errno::EACCES, JSON::ParserError => error
        render_bundle_error(code: 'invalid_bundle_input', message: error.message)
      end

      def render_bundle_error(
        code:,
        message:,
        status: nil,
        findings: nil,
        errors: nil,
        target_uid: nil,
        completed_targets: nil,
        path: nil
      )
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
          errors: errors,
          target_uid: target_uid,
          completed_targets: completed_targets,
          path: path
        }.compact
        puts JSON.pretty_generate(payload)
        exit 1
      end
    end
  end
end
