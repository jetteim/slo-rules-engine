# frozen_string_literal: true

require_relative '../artifact_integrity'

module SloRulesEngine
  module ReleaseBundle
    module Fingerprint
      module_function

      def content(value)
        ArtifactIntegrity::Fingerprint.content(value)
      end

      def text(value)
        ArtifactIntegrity::Fingerprint.text(value)
      end

      def artifact_content(artifact)
        content_type = fetch_value(artifact, :content_type)
        value = fetch_value(artifact, :content)
        content_type == 'text/x-ruby' ? text(value) : content(value)
      end

      def bundle_id(bundle, recompute_artifacts: false)
        artifacts = Array(fetch_value(bundle, :artifacts)).reject do |artifact|
          fetch_value(artifact, :kind) == 'onboarding_artifact_index'
        end.map do |artifact|
          fingerprint = if recompute_artifacts
                          artifact_content(artifact)
                        else
                          fetch_value(artifact, :fingerprint)
                        end
          identity = {
            uid: fetch_value(artifact, :uid),
            kind: fetch_value(artifact, :kind),
            scope: fetch_value(artifact, :scope),
            provider: fetch_value(artifact, :provider),
            fingerprint: fingerprint
          }.compact
          source = fetch_value(artifact, :source)
          identity[:source] = source if fetch_value(source, :type) == 'generated'
          identity
        end.sort_by { |artifact| artifact.fetch(:uid).to_s }

        identity = {
          schema_version: fetch_value(bundle, :schema_version),
          review: fetch_value(bundle, :review),
          targets: Array(fetch_value(bundle, :targets)).sort_by do |target|
            fetch_value(target, :uid).to_s
          end,
          artifacts: artifacts
        }
        transition = fetch_value(bundle, :transition)
        identity[:transition] = transition if transition
        "slo-bundle-#{content(identity)}"
      end

      def canonicalize(value)
        ArtifactIntegrity::Fingerprint.canonicalize(value)
      end

      def fetch_value(container, key)
        return container[key] if container.is_a?(Hash) && container.key?(key)
        return container[key.to_s] if container.is_a?(Hash) && container.key?(key.to_s)

        nil
      end
    end
  end
end
