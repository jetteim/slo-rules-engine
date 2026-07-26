# frozen_string_literal: true

require 'json'

module SloRulesEngine
  module ReleaseBundle
    class PlannerError < StandardError
      attr_reader :code, :findings

      def initialize(code, message, findings: [])
        @code = code
        @findings = findings
        super(message)
      end
    end

    class Planner
      def initialize(status_evaluator: StatusEvaluator.new)
        @status_evaluator = status_evaluator
      end

      def plan(bundle, target_runtime:)
        validate_predecessor!(bundle)
        runtime = normalize_runtime(target_runtime)
        validate_runtime_targets!(bundle, runtime)

        planned = deep_symbolize(bundle)
        artifacts = Array(fetch_value(planned, :artifacts))
        targets = Array(fetch_value(planned, :targets))
        targets.each do |target|
          plan_target!(planned, target, artifacts, runtime.fetch(fetch_value(target, :uid).to_s))
        end

        planned[:transition] = {
          action: 'plan',
          predecessor_bundle_id: fetch_value(bundle, :bundle_id),
          predecessor_lifecycle: fetch_value(bundle, :lifecycle)
        }
        planned[:lifecycle] = 'apply_ready'
        planned[:summary] = SummaryBuilder.new.build(
          review: fetch_value(planned, :review),
          targets: targets,
          artifacts: artifacts,
          findings: Array(fetch_value(planned, :findings))
        )
        planned[:bundle_id] = Fingerprint.bundle_id(planned)
        SchemaValidator.validate!(planned)
        validate_planned_bundle!(planned)
        planned
      end

      private

      def validate_predecessor!(bundle)
        status = @status_evaluator.evaluate(bundle)
        return if status[:valid] && status[:effective_lifecycle] == 'review_ready'

        lifecycle = status[:effective_lifecycle]
        code = case lifecycle
               when 'stale' then 'stale_bundle'
               when 'invalid' then 'invalid_bundle'
               when 'incomplete' then 'incomplete_bundle'
               else 'invalid_bundle_lifecycle'
               end
        raise PlannerError.new(
          code,
          "bundle plan requires a valid review_ready predecessor; effective lifecycle is #{lifecycle.inspect}",
          findings: status[:findings]
        )
      end

      def validate_planned_bundle!(bundle)
        status = @status_evaluator.evaluate(bundle)
        return if status[:valid] && status[:effective_lifecycle] == 'apply_ready'

        raise PlannerError.new(
          'invalid_planned_bundle',
          'generated apply_ready bundle failed status validation',
          findings: status[:findings]
        )
      end

      def normalize_runtime(target_runtime)
        target_runtime.to_h.each_with_object({}) do |(target_uid, config), normalized|
          normalized[target_uid.to_s] = config.to_h.each_with_object({}) do |(key, value), values|
            values[key.to_sym] = value
          end
        end
      end

      def validate_runtime_targets!(bundle, runtime)
        target_uids = Array(fetch_value(bundle, :targets)).map { |target| fetch_value(target, :uid).to_s }
        missing = target_uids - runtime.keys
        unknown = runtime.keys - target_uids
        findings = missing.map do |target_uid|
          finding(
            'missing_target_runtime',
            "targets[#{target_uid}].runtime",
            'explicit runtime configuration is required before planning this target'
          )
        end
        findings.concat(unknown.map do |target_uid|
          finding(
            'unknown_target_runtime',
            "target_runtime[#{target_uid}]",
            'runtime configuration does not match a packaged provider target'
          )
        end)
        return if findings.empty?

        code = missing.empty? ? 'unknown_target_runtime' : 'missing_target_runtime'
        raise PlannerError.new(code, 'target runtime configuration is incomplete', findings: findings)
      end

      def plan_target!(bundle, target, artifacts, runtime)
        target_uid = fetch_value(target, :uid).to_s
        manifest_uid = fetch_value(target, :manifest_artifact_uid)
        manifest_artifact = artifacts.find { |artifact| fetch_value(artifact, :uid) == manifest_uid }
        manifest = deep_symbolize(fetch_value(manifest_artifact, :content))
        plan = applier_for(target, runtime).plan(manifest).to_h
        normalized_plan = JSON.parse(JSON.generate(plan))
        validate_plan!(target, normalized_plan)

        credential_paths = CredentialScanner.paths(
          normalized_plan,
          "artifacts.change_plan[#{target_uid}].content"
        )
        raise CredentialError, credential_paths unless credential_paths.empty?

        plan_uid = "change-plan:#{target_uid}"
        artifacts.reject! { |artifact| fetch_value(artifact, :uid) == plan_uid }
        artifacts << {
          uid: plan_uid,
          kind: 'change_plan',
          scope: fetch_value(target, :scope),
          provider: fetch_value(target, :provider),
          content_type: 'application/json',
          fingerprint: Fingerprint.content(normalized_plan),
          source: {
            type: 'generated',
            predecessor_bundle_id: fetch_value(bundle, :bundle_id),
            target_uid: target_uid
          },
          content: normalized_plan
        }.compact
        artifacts.sort_by! { |artifact| fetch_value(artifact, :uid).to_s }
        target[:change_plan_artifact_uid] = plan_uid
      end

      def applier_for(target, runtime)
        automation_mode = fetch_value(target, :automation_mode)
        case automation_mode
        when 'manifest_bundle', 'external_generator'
          output_dir = runtime[:output_dir].to_s
          if output_dir.empty?
            raise invalid_runtime_error(target, 'output_dir is required for file-backed provider planning')
          end

          SloRulesEngine::Appliers::ManifestBundle.new(output_dir: File.expand_path(output_dir))
        when 'live_api'
          unless runtime[:backend].to_s == 'environment'
            raise invalid_runtime_error(
              target,
              'backend must be environment for live API planning; credentials remain outside the bundle'
            )
          end

          SloRulesEngine::Appliers::Datadog.new
        else
          raise PlannerError.new(
            'unsupported_target_automation',
            "provider target uses unsupported automation mode #{automation_mode.inspect}",
            findings: [
              finding(
                'unsupported_target_automation',
                "targets[#{fetch_value(target, :uid)}].automation_mode",
                'bundle planning supports manifest_bundle, external_generator, and live_api targets'
              )
            ]
          )
        end
      end

      def invalid_runtime_error(target, message)
        PlannerError.new(
          'invalid_target_runtime',
          message,
          findings: [
            finding(
              'invalid_target_runtime',
              "targets[#{fetch_value(target, :uid)}].runtime",
              message
            )
          ]
        )
      end

      def validate_plan!(target, plan)
        valid = fetch_value(plan, :provider) == fetch_value(target, :provider) &&
                fetch_value(plan, :mode) == 'dry_run' &&
                fetch_value(plan, :operations).is_a?(Array) &&
                fetch_value(plan, :summary).is_a?(Hash)
        return if valid

        raise PlannerError.new(
          'invalid_change_plan',
          'provider planner returned an invalid dry-run plan',
          findings: [
            finding(
              'invalid_change_plan',
              "targets[#{fetch_value(target, :uid)}].change_plan",
              'plan provider, mode, operations, or summary does not match the target contract'
            )
          ]
        )
      end

      def finding(code, path, message)
        { code: code, path: path, message: message }
      end

      def deep_symbolize(value)
        JSON.parse(JSON.generate(value), symbolize_names: true)
      end

      def fetch_value(container, key)
        return container[key] if container.is_a?(Hash) && container.key?(key)
        return container[key.to_s] if container.is_a?(Hash) && container.key?(key.to_s)

        nil
      end
    end
  end
end
