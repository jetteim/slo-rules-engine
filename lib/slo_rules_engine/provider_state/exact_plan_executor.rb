# frozen_string_literal: true

require 'fileutils'

module SloRulesEngine
  module ProviderState
    class ExactPlanExecutor
      def initialize(journal_dir:, clock: -> { Time.now.utc })
        Value.require_presence!('journal_dir', journal_dir)
        @journal_dir = File.expand_path(journal_dir)
        @clock = clock
      end

      def execute(approved_plan)
        approved_plan = validated_document(approved_plan)

        with_scope_lock(approved_plan) do
          applier(approved_plan).apply_exact(approved_plan)
        end
      end

      def resume(approved_plan)
        approved_plan = validated_document(approved_plan)

        with_scope_lock(approved_plan) do
          applier(approved_plan).resume_exact(approved_plan)
        end
      end

      def scope_lock_path(approved_plan)
        identity = {
          output_dir: File.expand_path(Value.fetch(approved_plan.runtime, :output_dir)),
          target_uid: Value.fetch(approved_plan.target, :uid)
        }
        File.join(
          @journal_dir,
          '.locks',
          "managed-scope-#{Fingerprint.content(identity)}.lock"
        )
      end

      private

      def validated_document(approved_plan)
        unless approved_plan.is_a?(ApprovedPlan::Document)
          approved_plan = ApprovedPlan::Loader.new.load(approved_plan)
        end
        mode = Value.fetch(approved_plan.target, :automation_mode)
        return approved_plan if ApprovedPlan::SUPPORTED_AUTOMATION_MODES.include?(mode)

        raise ApprovedPlan::Error.new(
          'unsupported_exact_plan_provider',
          "exact-plan execution does not support automation mode #{mode.inspect}",
          path: 'target.automation_mode'
        )
      end

      def applier(approved_plan)
        Appliers::ManifestBundle.new(
          output_dir: Value.fetch(approved_plan.runtime, :output_dir),
          journal_dir: @journal_dir,
          clock: @clock
        )
      end

      def with_scope_lock(approved_plan)
        path = scope_lock_path(approved_plan)
        FileUtils.mkdir_p(File.dirname(path))
        File.open(path, File::RDWR | File::CREAT, 0o600) do |lock|
          unless lock.flock(File::LOCK_EX | File::LOCK_NB)
            raise ApprovedPlan::Error.new(
              'approved_plan_scope_busy',
              'another exact apply is active for the approved managed scope',
              path: path
            )
          end

          yield
        ensure
          lock.flock(File::LOCK_UN)
        end
      end
    end
  end
end
