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

      private

      def manifest_path(manifest)
        File.join(@output_dir, manifest.fetch(:service), manifest.fetch(:provider), 'manifest.json')
      end
    end
  end
end
