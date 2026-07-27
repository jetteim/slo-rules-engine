# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'yaml'

module SloRulesEngine
  module Appliers
    class ManifestBundle
      def initialize(
        output_dir:,
        journal_dir: nil,
        clock: -> { Time.now.utc },
        verifier: ProviderState::ManagedFileVerifier.new
      )
        @output_dir = output_dir
        journal_store = if journal_dir
                          ProviderState::JournalStore.new(root_dir: journal_dir, clock: clock)
                        end
        @executor = ProviderState::JournaledExecutor.new(
          journal_store: journal_store,
          clock: clock,
          verifier: verifier
        )
      end

      def plan(manifest, mode: 'dry_run')
        manifest = SloRulesEngine::ManifestSchemaValidator.validate!(manifest)
        operations = [managed_manifest_operation(manifest, plan_action: true)]
        operations.concat(managed_bundle_resource_operations(manifest, plan_action: true))
        operations.concat(external_generator_input_operations(manifest, plan_action: true))
        operations << handoff_operation(manifest) if manifest.fetch(:provider) == 'sloth'

        apply_plan(manifest, mode: mode, operations: operations)
      end

      def apply(manifest)
        manifest = SloRulesEngine::ManifestSchemaValidator.validate!(manifest)
        @executor.execute(plan(manifest, mode: 'live')) do |operation|
          write_operation(operation)
        end
      end

      def apply_exact(approved_plan)
        unless approved_plan.is_a?(ProviderState::ApprovedPlan::Document)
          raise ProviderState::ApprovedPlan::Error.new(
            'invalid_approved_plan',
            'exact apply requires an approved provider plan'
          )
        end
        approved_provider_plan = approved_plan.provider_plan
        approved_output_dir = File.expand_path(
          ProviderState::Value.fetch(approved_plan.runtime, :output_dir)
        )
        unless File.expand_path(@output_dir) == approved_output_dir
          raise ProviderState::ApprovedPlan::Error.new(
            'invalid_approved_plan_runtime',
            'approved output directory does not match the exact-plan executor',
            path: 'runtime.output_dir'
          )
        end

        manifest = ProviderState::Value.copy(approved_provider_plan.desired_state.resources)
        current_provider_plan = plan(manifest).provider_state_plan
        unless current_provider_plan.fingerprint == approved_provider_plan.fingerprint
          raise ProviderState::ApprovedPlan::Error.new(
            'stale_approved_plan',
            'managed-file state changed after plan approval; create and approve a new plan',
            path: 'provider_plan.observed_state',
            findings: [
              {
                code: 'approved_plan_state_changed',
                path: 'provider_plan.observed_state',
                message: 'immediate managed-file state does not match the approved plan',
                expected_plan_fingerprint: approved_provider_plan.fingerprint,
                actual_plan_fingerprint: current_provider_plan.fingerprint,
                expected_observed_state_fingerprint: approved_provider_plan.observed_state.fingerprint,
                actual_observed_state_fingerprint: current_provider_plan.observed_state.fingerprint
              }
            ]
          )
        end

        exact_plan = exact_apply_plan(approved_provider_plan)
        @executor.execute(
          exact_plan,
          approved_plan_reference: approved_plan.reference
        ) do |operation|
          write_operation(operation)
        end
      end

      def diff(manifest)
        manifest = SloRulesEngine::ManifestSchemaValidator.validate!(manifest)
        operations = [
          managed_manifest_operation(manifest, plan_action: false),
          *managed_bundle_resource_operations(manifest, plan_action: false),
          *external_generator_input_operations(manifest, plan_action: false)
        ]
        apply_plan(
          manifest,
          mode: 'diff',
          operations: operations
        )
      end

      def import(manifest)
        manifest = SloRulesEngine::ManifestSchemaValidator.validate!(manifest)
        path = manifest_path(manifest)
        actual = File.exist?(path) ? JSON.parse(File.read(path), symbolize_names: true) : nil
        findings = actual.nil? ? [missing_manifest_finding(path)] : []
        if manifest.fetch(:provider) == 'sloth'
          inputs = sloth_specs(manifest).each_index.map do |index|
            input_path = sloth_spec_path(manifest, index)
            spec = read_yaml(input_path)
            findings << missing_external_generator_input_finding(input_path, index) if spec.nil?
            {
              source: "artifacts.sloth_specs[#{index}]",
              path: input_path,
              spec: spec
            }
          end
          return imported_state(
            manifest,
            source: 'external_generator_files',
            state: {
              manifest: actual,
              external_generator_inputs: inputs
            },
            findings: findings
          )
        end
        unless manifest.fetch(:provider) == 'prometheus_stack'
          return imported_state(
            manifest,
            source: 'manifest_file',
            state: actual,
            findings: findings
          )
        end

        bundle_files = managed_bundle_resource_entries(manifest).map do |entry|
          resource = read_yaml(entry.fetch(:path))
          if resource.nil?
            findings << missing_bundle_file_finding(entry)
          end
          {
            target: entry.fetch(:target),
            source: entry.fetch(:source),
            path: entry.fetch(:path),
            resource: resource
          }
        end

        imported_state(
          manifest,
          source: 'manifest_bundle',
          state: {
            manifest: actual,
            bundle_files: bundle_files
          },
          findings: findings
        )
      end

      def prune(manifest, mode: 'dry_run')
        manifest = SloRulesEngine::ManifestSchemaValidator.validate!(manifest)
        operations = prune_operations(manifest)

        plan = apply_plan(manifest, mode: mode, operations: operations)
        return plan unless mode == 'live'

        @executor.execute(plan) { |operation| delete_operation(operation) }
      end

      private

      def exact_apply_plan(provider_plan)
        operations = provider_plan.changes.map.with_index do |change, index|
          unless %w[write noop handoff].include?(change.action)
            raise ProviderState::ApprovedPlan::Error.new(
              'unsupported_approved_operation',
              "file-backed exact apply cannot execute #{change.action.inspect}",
              path: "provider_plan.changes[#{index}].action"
            )
          end

          ApplyOperation.new(
            action: change.action,
            target: change.target,
            name: change.name,
            source: change.source,
            payload: ProviderState::Value.copy(change.desired),
            backend_id: ProviderState::Value.copy(change.provider_resource_id),
            actual: ProviderState::Value.copy(change.observed),
            changes: ProviderState::Value.copy(change.changed_paths),
            match_identity: ProviderState::Value.copy(change.match_identity),
            risk: ProviderState::Value.copy(change.risk)
          )
        end
        ApplyPlan.new(
          provider: provider_plan.provider,
          service: provider_plan.service,
          mode: 'live',
          operations: operations,
          findings: provider_plan.findings.map(&:to_h),
          desired_state: provider_plan.desired_state,
          observed_state: provider_plan.observed_state
        )
      end

      def write_operation(operation)
        path = operation.payload.fetch(:path)
        FileUtils.mkdir_p(File.dirname(path))
        bytes_written = case operation.target
                        when 'manifest_file'
                          File.write(path, JSON.pretty_generate(operation.payload.fetch(:manifest)))
                        when 'external_generator_input'
                          File.write(path, YAML.dump(json_safe(operation.payload.fetch(:spec))))
                        when /\Aprometheus_stack\./
                          File.write(path, YAML.dump(json_safe(operation.payload.fetch(:resource))))
                        else
                          raise UnsupportedApplyAction, "unsupported manifest-bundle target #{operation.target.inspect}"
                        end
        {
          provider_resource_id: path,
          path: path,
          bytes_written: bytes_written
        }
      end

      def delete_operation(operation)
        path = operation.payload.fetch(:path)
        File.delete(path)
        {
          provider_resource_id: path,
          path: path,
          deleted: true
        }
      end

      def apply_plan(manifest, mode:, operations:, findings: [])
        ApplyPlan.new(
          provider: manifest.fetch(:provider),
          service: manifest.fetch(:service),
          mode: mode,
          operations: operations,
          findings: findings,
          desired_state: ProviderState::DesiredState.new(
            provider: manifest.fetch(:provider),
            service: manifest.fetch(:service),
            source: 'provider_manifest',
            resources: manifest
          ),
          observed_state: ProviderState::ObservedState.new(
            provider: manifest.fetch(:provider),
            service: manifest.fetch(:service),
            source: 'manifest_bundle',
            resources: observed_resources(operations)
          )
        )
      end

      def observed_resources(operations)
        {
          entries: operations.filter_map do |operation|
            next if operation.target == 'external_generator'

            {
              target: operation.target,
              name: operation.name,
              source: operation.source,
              path: operation.payload&.fetch(:path, nil),
              present: !operation.actual.nil? || operation.action == 'delete',
              resource: operation.actual
            }.compact
          end
        }
      end

      def imported_state(manifest, source:, state:, findings:)
        ImportedState.new(
          provider: manifest.fetch(:provider),
          service: manifest.fetch(:service),
          source: source,
          state: state,
          findings: findings,
          desired_state: ProviderState::DesiredState.new(
            provider: manifest.fetch(:provider),
            service: manifest.fetch(:service),
            source: 'provider_manifest',
            resources: manifest
          ),
          observed_state: ProviderState::ObservedState.new(
            provider: manifest.fetch(:provider),
            service: manifest.fetch(:service),
            source: source,
            resources: state
          )
        )
      end

      def managed_manifest_operation(manifest, plan_action:)
        path = manifest_path(manifest)
        actual = File.exist?(path) ? JSON.parse(File.read(path), symbolize_names: true) : nil
        changes = actual ? SloRulesEngine::StateDiff.changed_paths(manifest, actual) : ['manifest']

        ApplyOperation.new(
          action: file_action(actual, changes, plan_action: plan_action),
          target: 'manifest_file',
          name: "#{manifest.fetch(:service)} #{manifest.fetch(:provider)} manifest",
          source: 'manifest',
          payload: { path: path, manifest: manifest },
          actual: actual,
          changes: changes
        )
      end

      def external_generator_input_operations(manifest, plan_action:)
        return [] unless manifest.fetch(:provider) == 'sloth'

        sloth_specs(manifest).each_with_index.map do |spec, index|
          path = sloth_spec_path(manifest, index)
          desired = json_safe(spec)
          actual = File.exist?(path) ? YAML.safe_load(File.read(path), permitted_classes: [], aliases: false) : nil
          changes = actual ? SloRulesEngine::StateDiff.changed_paths(desired, actual) : ['external_generator_input']

          ApplyOperation.new(
            action: file_action(actual, changes, plan_action: plan_action),
            target: 'external_generator_input',
            name: "#{manifest.fetch(:service)} sloth generator input #{index + 1}",
            source: "artifacts.sloth_specs[#{index}]",
            payload: { path: path, spec: spec },
            actual: actual,
            changes: changes
          )
        end
      end

      def managed_bundle_resource_operations(manifest, plan_action:)
        managed_bundle_resource_entries(manifest).map do |entry|
          desired = json_safe(entry.fetch(:resource))
          actual = read_yaml(entry.fetch(:path))
          changes = actual ? SloRulesEngine::StateDiff.changed_paths(desired, actual) : ['managed_bundle_resource']

          ApplyOperation.new(
            action: file_action(actual, changes, plan_action: plan_action),
            target: entry.fetch(:target),
            name: entry.fetch(:name),
            source: entry.fetch(:source),
            payload: {
              path: entry.fetch(:path),
              resource: entry.fetch(:resource)
            },
            actual: actual,
            changes: changes
          )
        end
      end

      def file_action(actual, changes, plan_action:)
        return 'write' if plan_action && (actual.nil? || !changes.empty?)
        return 'noop' if plan_action
        return 'create' if actual.nil?
        return 'noop' if changes.empty?

        'update'
      end

      def prune_operations(manifest)
        paths = [
          {
            path: manifest_path(manifest),
            target: 'manifest_file',
            name: "#{manifest.fetch(:service)} #{manifest.fetch(:provider)} manifest",
            source: 'manifest'
          }
        ]
        paths.concat(sloth_specs(manifest).each_index.map do |index|
          {
            path: sloth_spec_path(manifest, index),
            target: 'external_generator_input',
            name: "#{manifest.fetch(:service)} sloth generator input #{index + 1}",
            source: "artifacts.sloth_specs[#{index}]"
          }
        end)
        paths.concat(managed_bundle_resource_entries(manifest).map do |entry|
          entry.reject { |key, _value| key == :resource }
        end)

        paths.map do |entry|
          exists = File.exist?(entry.fetch(:path))
          ApplyOperation.new(
            action: exists ? 'delete' : 'noop',
            target: entry.fetch(:target),
            name: entry.fetch(:name),
            source: entry.fetch(:source),
            payload: { path: entry.fetch(:path) }
          )
        end
      end

      def manifest_path(manifest)
        File.join(@output_dir, manifest.fetch(:service), manifest.fetch(:provider), 'manifest.json')
      end

      def sloth_specs(manifest)
        artifacts = manifest.fetch(:artifacts)
        Array(artifacts[:sloth_specs] || artifacts['sloth_specs'])
      end

      def sloth_spec_path(manifest, index)
        filename = sloth_specs(manifest).length == 1 ? 'sloth.yaml' : "sloth-#{index + 1}.yaml"
        File.join(@output_dir, manifest.fetch(:service), manifest.fetch(:provider), 'generated', filename)
      end

      def managed_bundle_resource_entries(manifest)
        return [] unless manifest.fetch(:provider) == 'prometheus_stack'

        [
          {
            artifact: :prometheus_rule_resources,
            basename: 'prometheus-rules',
            target: 'prometheus_stack.prometheus_rule',
            description: 'PrometheusRule'
          },
          {
            artifact: :grafana_dashboard_resources,
            basename: 'grafana-dashboards',
            target: 'prometheus_stack.grafana_dashboard',
            description: 'Grafana dashboard ConfigMap'
          },
          {
            artifact: :alertmanager_route_bundles,
            basename: 'alertmanager-routes',
            target: 'prometheus_stack.alertmanager_route_intent',
            description: 'Alertmanager route intent'
          }
        ].flat_map do |spec|
          resources = artifact_collection(manifest, spec.fetch(:artifact))
          resources.each_with_index.map do |resource, index|
            filename = indexed_filename(spec.fetch(:basename), resources.length, index)
            {
              path: File.join(
                @output_dir,
                manifest.fetch(:service),
                manifest.fetch(:provider),
                'generated',
                filename
              ),
              target: spec.fetch(:target),
              name: "#{manifest.fetch(:service)} #{spec.fetch(:description)} #{index + 1}",
              source: "artifacts.#{spec.fetch(:artifact)}[#{index}]",
              resource: resource
            }
          end
        end
      end

      def artifact_collection(manifest, key)
        artifacts = manifest.fetch(:artifacts)
        Array(artifacts[key] || artifacts[key.to_s])
      end

      def indexed_filename(basename, count, index)
        suffix = count == 1 ? '' : "-#{index + 1}"
        "#{basename}#{suffix}.yaml"
      end

      def handoff_operation(manifest)
        output_dir = File.join(@output_dir, manifest.fetch(:service), manifest.fetch(:provider), 'generated')
        input_specs = sloth_specs(manifest).each_index.map { |index| sloth_spec_path(manifest, index) }
        commands = input_specs.map { |path| "sloth generate -i #{path} -o #{output_dir}" }

        ApplyOperation.new(
          action: 'handoff',
          target: 'external_generator',
          name: "#{manifest.fetch(:service)} #{manifest.fetch(:provider)} external generation handoff",
          source: 'manifest',
          payload: {
            command: commands.empty? ? "sloth generate -i #{manifest_path(manifest)} -o #{output_dir}" : commands.join(' && '),
            commands: commands,
            input_manifest: manifest_path(manifest),
            input_spec: input_specs.fetch(0, nil),
            input_specs: input_specs,
            manifest_review_report: manifest_review_report_path(manifest),
            manifest_review_command: manifest_review_command(manifest),
            manifest_review_freshness: {
              required: true,
              report: manifest_review_report_path(manifest),
              finding_codes: %w[stale_manifest_review_report stale_handoff_review_report]
            },
            output_dir: output_dir,
            review_required: true
          }
        )
      end

      def json_safe(value)
        JSON.parse(JSON.generate(value))
      end

      def read_yaml(path)
        return nil unless File.exist?(path)

        YAML.safe_load(File.read(path), permitted_classes: [], aliases: false)
      end

      def manifest_review_command(manifest)
        "rules-ctl manifest-review --provider=#{manifest.fetch(:provider)} --manifest=#{manifest_path(manifest)} --report=#{manifest_review_report_path(manifest)}"
      end

      def manifest_review_report_path(manifest)
        File.join(@output_dir, 'manifest-review', "#{manifest.fetch(:provider)}.json")
      end

      def missing_manifest_finding(path)
        {
          code: 'missing_managed_manifest',
          path: path,
          message: "managed manifest does not exist at #{path}"
        }
      end

      def missing_bundle_file_finding(entry)
        {
          code: 'missing_managed_bundle_file',
          target: entry.fetch(:target),
          source: entry.fetch(:source),
          path: entry.fetch(:path),
          message: "managed bundle file does not exist at #{entry.fetch(:path)}"
        }
      end

      def missing_external_generator_input_finding(path, index)
        {
          code: 'missing_external_generator_input',
          target: 'external_generator_input',
          source: "artifacts.sloth_specs[#{index}]",
          path: path,
          message: "managed external-generator input does not exist at #{path}"
        }
      end
    end
  end
end
