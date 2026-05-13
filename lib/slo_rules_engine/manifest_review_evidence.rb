# frozen_string_literal: true

module SloRulesEngine
  module ManifestReviewEvidenceValidator
    module_function

    def validate(manifests)
      result = ValidationResult.new
      Array(manifests).each_with_index do |manifest, index|
        provenance = fetch_value(manifest, :review_provenance)
        path = "manifests[#{index}].review_provenance"
        unless provenance.is_a?(Hash)
          result.error(path, 'is required before live apply')
          next
        end

        accepted = fetch_value(provenance, :accepted_candidate_uids)
        unless accepted.is_a?(Array) && !accepted.empty?
          result.error("#{path}.accepted_candidate_uids", 'must include at least one accepted candidate before live apply')
        end
      end
      result
    end

    def fetch_value(container, key)
      return container[key] if container.is_a?(Hash) && container.key?(key)
      return container[key.to_s] if container.is_a?(Hash) && container.key?(key.to_s)

      nil
    end
  end
end
