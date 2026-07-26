# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'yaml'

module SloRulesEngine
  module Appliers
    class ManifestBundle
      def initialize(output_dir:)
        @output_dir = output_dir
      end

      def plan(manifest, mode: 'dry_run')
        manifest = SloRulesEngine::ManifestSchemaValidator.validate!(manifest)
        operations = [managed_manifest_operation(manifest, plan_action: true)]
        operations.concat(managed_bundle_resource_operations(manifest, plan_action: true))
        operations.concat(external_generator_input_operations(manifest, plan_action: true))
        operations << handoff_operation(manifest) if manifest.fetch(:provider) == 'sloth'

        ApplyPlan.new(
          provider: manifest.fetch(:provider),
          mode: mode,
          operations: operations
        )
      end

      def apply(manifest)
        manifest = SloRulesEngine::ManifestSchemaValidator.validate!(manifest)
        plan(manifest, mode: 'live').tap do |apply_plan|
          apply_plan.operations.each do |operation|
            next unless operation.action == 'write'

            path = operation.payload.fetch(:path)
            FileUtils.mkdir_p(File.dirname(path))
            case operation.target
            when 'manifest_file'
              File.write(path, JSON.pretty_generate(operation.payload.fetch(:manifest)))
            when 'external_generator_input'
              File.write(path, YAML.dump(json_safe(operation.payload.fetch(:spec))))
            when /\Aprometheus_stack\./
              File.write(path, YAML.dump(json_safe(operation.payload.fetch(:resource))))
            end
          end
        end
      end

      def diff(manifest)
        manifest = SloRulesEngine::ManifestSchemaValidator.validate!(manifest)
        ApplyPlan.new(
          provider: manifest.fetch(:provider),
          mode: 'diff',
          operations: [
            managed_manifest_operation(manifest, plan_action: false),
            *managed_bundle_resource_operations(manifest, plan_action: false),
            *external_generator_input_operations(manifest, plan_action: false)
          ]
        )
      end

      def import(manifest)
        manifest = SloRulesEngine::ManifestSchemaValidator.validate!(manifest)
        path = manifest_path(manifest)
        actual = File.exist?(path) ? JSON.parse(File.read(path), symbolize_names: true) : nil
        findings = actual.nil? ? [missing_manifest_finding(path)] : []
        return imported_manifest_state(manifest, actual, findings) unless manifest.fetch(:provider) == 'prometheus_stack'

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

        ImportedState.new(
          provider: manifest.fetch(:provider),
          service: manifest.fetch(:service),
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

        ApplyPlan.new(
          provider: manifest.fetch(:provider),
          mode: mode,
          operations: operations
        ).tap do |plan|
          next unless mode == 'live'

          plan.operations.each do |operation|
            next unless operation.action == 'delete'

            File.delete(operation.payload.fetch(:path))
          end
        end
      end

      private

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

      def imported_manifest_state(manifest, actual, findings)
        ImportedState.new(
          provider: manifest.fetch(:provider),
          service: manifest.fetch(:service),
          source: 'manifest_file',
          state: actual,
          findings: findings
        )
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
    end
  end
end
