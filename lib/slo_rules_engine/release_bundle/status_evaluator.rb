# frozen_string_literal: true

require 'json'

module SloRulesEngine
  module ReleaseBundle
    class StatusEvaluator
      def evaluate(bundle)
        schema = SchemaValidator.validate(bundle)
        findings = schema.errors.map do |error|
          {
            code: 'invalid_bundle_schema',
            path: error.path,
            message: error.message
          }
        end
        artifacts = Array(fetch_value(bundle, :artifacts))
        findings.concat(artifact_fingerprint_findings(artifacts))
        findings.concat(bundle_identity_findings(bundle))
        findings.concat(source_findings(artifacts))
        findings.concat(Array(fetch_value(bundle, :findings)).map { |finding| normalize_hash(finding) })
        findings = findings.uniq
        lifecycle = effective_lifecycle(fetch_value(bundle, :lifecycle), findings)

        {
          valid: %w[review_ready apply_ready applied verified].include?(lifecycle),
          bundle_id: fetch_value(bundle, :bundle_id),
          schema_version: fetch_value(bundle, :schema_version),
          declared_lifecycle: fetch_value(bundle, :lifecycle),
          effective_lifecycle: lifecycle,
          review: fetch_value(bundle, :review),
          targets: fetch_value(bundle, :targets),
          summary: {
            artifact_count: artifacts.length,
            target_count: Array(fetch_value(bundle, :targets)).length,
            fresh_sources: artifacts.length - findings.count { |finding| source_finding?(finding) },
            stale_sources: findings.count { |finding| source_finding?(finding) },
            finding_count: findings.length
          },
          findings: findings
        }
      end

      private

      def artifact_fingerprint_findings(artifacts)
        artifacts.each_with_index.filter_map do |artifact, index|
          expected = fetch_value(artifact, :fingerprint)
          actual = Fingerprint.artifact_content(artifact)
          next if expected == actual

          {
            code: 'artifact_fingerprint_mismatch',
            path: "artifacts[#{index}].fingerprint",
            message: 'packaged artifact content does not match its fingerprint',
            expected: expected,
            actual: actual
          }
        end
      end

      def bundle_identity_findings(bundle)
        expected = fetch_value(bundle, :bundle_id)
        actual = Fingerprint.bundle_id(bundle, recompute_artifacts: true)
        return [] if expected == actual

        [
          {
            code: 'bundle_identity_mismatch',
            path: 'bundle_id',
            message: 'bundle identity does not match packaged content',
            expected: expected,
            actual: actual
          }
        ]
      end

      def source_findings(artifacts)
        artifacts.each_with_index.filter_map do |artifact, index|
          source = fetch_value(artifact, :source)
          path = fetch_value(source, :path)
          unless File.exist?(path.to_s)
            next {
              code: 'source_artifact_missing',
              path: "artifacts[#{index}].source.path",
              message: "source artifact does not exist at #{path}"
            }
          end

          content = source_content(path, artifact)
          actual = if fetch_value(artifact, :content_type) == 'text/x-ruby'
                     Fingerprint.text(content)
                   else
                     Fingerprint.content(content)
                   end
          expected = fetch_value(artifact, :fingerprint)
          next if expected == actual

          {
            code: 'source_artifact_changed',
            path: "artifacts[#{index}].source.path",
            message: "source artifact changed after bundle creation at #{path}",
            expected: expected,
            actual: actual
          }
        end
      end

      def source_content(path, artifact)
        return File.read(path) if fetch_value(artifact, :content_type) == 'text/x-ruby'

        parsed = JSON.parse(File.read(path))
        if fetch_value(artifact, :kind) == 'change_plan' && parsed.is_a?(Array) && parsed.length == 1
          parsed.fetch(0)
        else
          parsed
        end
      rescue JSON::ParserError
        {}
      end

      def effective_lifecycle(declared, findings)
        codes = findings.map { |finding| finding[:code].to_s }
        return 'invalid' if codes.any? do |code|
          %w[
            invalid_bundle_schema
            artifact_fingerprint_mismatch
            bundle_identity_mismatch
          ].include?(code)
        end
        return 'stale' if codes.any? { |code| code.start_with?('stale_') || code.start_with?('source_artifact_') }
        return 'incomplete' unless codes.empty?

        declared
      end

      def source_finding?(finding)
        finding[:code].to_s.start_with?('source_artifact_')
      end

      def normalize_hash(value)
        value.to_h.each_with_object({}) { |(key, entry), normalized| normalized[key.to_sym] = entry }
      end

      def fetch_value(container, key)
        return container[key] if container.is_a?(Hash) && container.key?(key)
        return container[key.to_s] if container.is_a?(Hash) && container.key?(key.to_s)

        nil
      end
    end
  end
end
