# frozen_string_literal: true

require 'digest'
require 'json'

module SloRulesEngine
  module ReleaseBundle
    module Fingerprint
      module_function

      def content(value)
        Digest::SHA256.hexdigest(JSON.generate(canonicalize(value)))
      end

      def text(value)
        Digest::SHA256.hexdigest(value.to_s)
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
        case value
        when Hash
          value.keys.sort_by(&:to_s).each_with_object({}) do |key, canonical|
            canonical[key.to_s] = canonicalize(value[key])
          end
        when Array
          value.map { |entry| canonicalize(entry) }
        else
          value
        end
      end

      def fetch_value(container, key)
        return container[key] if container.is_a?(Hash) && container.key?(key)
        return container[key.to_s] if container.is_a?(Hash) && container.key?(key.to_s)

        nil
      end
    end
  end
end
