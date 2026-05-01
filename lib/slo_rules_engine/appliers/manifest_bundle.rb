# frozen_string_literal: true

require 'fileutils'

module SloRulesEngine
  module Appliers
    class ManifestBundle
      def initialize(output_dir:)
        @output_dir = output_dir
      end

      def plan(manifest, mode: 'dry_run')
        ApplyPlan.new(
          provider: manifest.fetch(:provider),
          mode: mode,
          operations: [
            ApplyOperation.new(
              action: 'write',
              target: 'manifest_file',
              name: "#{manifest.fetch(:service)} #{manifest.fetch(:provider)} manifest",
              source: 'manifest',
              payload: { path: manifest_path(manifest), manifest: manifest }
            )
          ]
        )
      end

      def apply(manifest)
        plan(manifest, mode: 'live').tap do |apply_plan|
          apply_plan.operations.each do |operation|
            path = operation.payload.fetch(:path)
            FileUtils.mkdir_p(File.dirname(path))
            File.write(path, JSON.pretty_generate(operation.payload.fetch(:manifest)))
          end
        end
      end

      def diff(manifest)
        path = manifest_path(manifest)
        actual = File.exist?(path) ? JSON.parse(File.read(path), symbolize_names: true) : nil
        changes = actual ? SloRulesEngine::StateDiff.changed_paths(manifest, actual) : ['manifest']
        action = if actual.nil?
                   'create'
                 elsif changes.empty?
                   'noop'
                 else
                   'update'
                 end

        ApplyPlan.new(
          provider: manifest.fetch(:provider),
          mode: 'diff',
          operations: [
            ApplyOperation.new(
              action: action,
              target: 'manifest_file',
              name: "#{manifest.fetch(:service)} #{manifest.fetch(:provider)} manifest",
              source: 'manifest',
              payload: { path: path, manifest: manifest },
              actual: actual,
              changes: changes
            )
          ]
        )
      end

      private

      def manifest_path(manifest)
        File.join(@output_dir, manifest.fetch(:service), manifest.fetch(:provider), 'manifest.json')
      end
    end
  end
end
