# frozen_string_literal: true

require 'json'
require 'optparse'

module SloRulesEngine
  module CLI
    module PlanCommands
      def plan(argv)
        subcommand = argv.shift
        case subcommand
        when 'approve'
          plan_approve(argv)
        when 'status'
          plan_status(argv)
        when 'apply'
          plan_apply(argv)
        else
          abort_usage('usage: plan approve|status|apply')
        end
      end

      def plan_approve(argv)
        bundle_path = argv.shift
        target_uid = nil
        reviewer = nil
        reviewed_at = nil
        notes = []
        output_path = nil
        parser = OptionParser.new do |opts|
          opts.on('--target=SERVICE/PROVIDER', 'Target UID from the apply-ready bundle') do |value|
            target_uid = value
          end
          opts.on('--reviewer=IDENTITY', 'Reviewer approving this exact provider plan') do |value|
            reviewer = value
          end
          opts.on('--reviewed-at=TIMESTAMP', 'Explicit ISO 8601 approval timestamp') do |value|
            reviewed_at = value
          end
          opts.on('--note=TEXT', 'Approval note; repeatable') { |value| notes << value }
          opts.on('--output=FILE', 'Write the immutable approved provider plan') do |value|
            output_path = value
          end
        end
        parser.parse!(argv)
        abort_usage('missing apply-ready bundle path') if bundle_path.to_s.empty?
        abort_usage('missing --target') if target_uid.to_s.empty?
        abort_usage('missing --reviewer') if reviewer.to_s.empty?
        abort_usage('missing --reviewed-at') if reviewed_at.to_s.empty?
        abort_usage('missing --output') if output_path.to_s.empty?
        abort_usage('unexpected arguments') unless argv.empty?

        bundle = JSON.parse(File.read(bundle_path), symbolize_names: true)
        approved_plan = ProviderState::ApprovedPlan::Builder.new.build(
          bundle,
          target_uid: target_uid,
          reviewer: reviewer,
          reviewed_at: reviewed_at,
          notes: notes
        )
        ProviderState::ApprovedPlan::Store.new.write(output_path, approved_plan)
        puts JSON.pretty_generate(approved_plan)
      rescue ProviderState::ApprovedPlan::Error => error
        render_approved_plan_error(error)
      rescue ReleaseBundle::SchemaError => error
        render_approved_plan_error(
          ProviderState::ApprovedPlan::Error.new(
            'invalid_source_bundle',
            error.message,
            findings: error.result.errors.map(&:to_h)
          )
        )
      rescue Errno::ENOENT, Errno::EACCES, JSON::ParserError => error
        render_approved_plan_error(
          ProviderState::ApprovedPlan::Error.new('invalid_approved_plan_input', error.message)
        )
      end

      def plan_status(argv)
        path = argv.shift
        abort_usage('missing approved provider plan path') if path.to_s.empty?
        abort_usage('unexpected arguments') unless argv.empty?

        payload = JSON.parse(File.read(path), symbolize_names: true)
        status = ProviderState::ApprovedPlan::StatusEvaluator.new.evaluate(payload)
        puts JSON.pretty_generate(status)
        exit 1 unless status[:valid]
      rescue Errno::ENOENT, Errno::EACCES, JSON::ParserError => error
        render_approved_plan_error(
          ProviderState::ApprovedPlan::Error.new('invalid_approved_plan_input', error.message)
        )
      end

      def plan_apply(argv)
        path = argv.shift
        confirm = false
        journal_dir = nil
        parser = OptionParser.new do |opts|
          opts.on('--confirm', 'Execute only the approved provider operations') { confirm = true }
          opts.on('--journal-dir=DIR', 'Durable exact-plan operation journal directory') do |value|
            journal_dir = value
          end
        end
        parser.parse!(argv)
        abort_usage('missing approved provider plan path') if path.to_s.empty?
        abort_usage('exact plan apply requires --confirm') unless confirm
        abort_usage('exact plan apply requires --journal-dir') if journal_dir.to_s.empty?
        abort_usage('unexpected arguments') unless argv.empty?

        payload = JSON.parse(File.read(path), symbolize_names: true)
        approved_plan = ProviderState::ApprovedPlan::Loader.new.load(payload)
        result = ProviderState::ExactPlanExecutor.new(journal_dir: journal_dir).execute(approved_plan)
        puts JSON.pretty_generate(result.to_h)
        exit 1 if failed_execution?(result)
      rescue ProviderState::ApprovedPlan::Error => error
        render_approved_plan_error(
          error,
          approved_plan_id: ProviderState::Value.fetch(payload, :approved_plan_id)
        )
      rescue ProviderState::JournalConflict => error
        render_approved_plan_error(
          ProviderState::ApprovedPlan::Error.new(
            'operation_journal_conflict',
            error.message,
            path: error.path
          ),
          approved_plan_id: ProviderState::Value.fetch(payload, :approved_plan_id)
        )
      rescue Errno::ENOENT, Errno::EACCES, JSON::ParserError => error
        render_approved_plan_error(
          ProviderState::ApprovedPlan::Error.new('invalid_approved_plan_input', error.message)
        )
      end

      def render_approved_plan_error(error, approved_plan_id: nil)
        puts JSON.pretty_generate(
          {
            valid: false,
            approved_plan_id: approved_plan_id,
            error: {
              code: error.code,
              message: error.message
            },
            path: error.path,
            findings: error.findings
          }.compact
        )
        exit 1
      end
    end
  end
end
