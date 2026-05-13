# frozen_string_literal: true

module SloRulesEngine
  module Onboarding
    class HandoffValidator
      REQUIRED_CANDIDATE_FIELDS = %i[
        sli_uid
        signal
        metric
        rationale
        confidence
        explanation
        evidence
        proposed_slo
      ].freeze

      REQUIRED_SLO_FIELDS = %i[
        uid
        objective
        success_condition
        calculation_basis
      ].freeze

      Result = Struct.new(:path, :label, :provider, :accepted_candidate_count, :errors, :warnings, keyword_init: true) do
        def valid?
          errors.empty?
        end

        def error(path, message)
          errors << ValidationMessage.new(path: path, message: message)
        end

        def warning(path, message)
          warnings << ValidationMessage.new(path: path, message: message)
        end

        def to_h
          {
            valid: valid?,
            path: path,
            label: label,
            provider: provider,
            accepted_candidate_count: accepted_candidate_count,
            errors: errors.map(&:to_h),
            warnings: warnings.map(&:to_h)
          }.compact
        end
      end

      def validate_file(path)
        packet = JSON.parse(File.read(path), symbolize_names: true)
        validate(packet, path: path)
      end

      def validate(packet, path: nil)
        review = packet[:review] || {}
        accepted = Array(review[:accepted_candidate_uids]).map(&:to_s)
        result = Result.new(
          path: path,
          label: packet[:label],
          provider: packet[:provider],
          accepted_candidate_count: accepted.length,
          errors: [],
          warnings: []
        )

        validate_presence(result, 'label', packet[:label])
        validate_presence(result, 'provider', packet[:provider])
        validate_presence(result, 'scope', packet[:scope])
        validate_review(result, review)
        validate_candidates(result, packet, accepted)
        result
      end

      private

      def validate_review(result, review)
        result.error('review.status', 'must be reviewed before provider handoff') unless review[:status].to_s == 'reviewed'
        accepted = Array(review[:accepted_candidate_uids]).map(&:to_s)
        rejected = Array(review[:rejected_candidate_uids]).map(&:to_s)
        result.error('review.accepted_candidate_uids', 'must include at least one accepted candidate') if accepted.empty?
        duplicate = (accepted & rejected).first
        result.error('review', "candidate #{duplicate.inspect} cannot be both accepted and rejected") if duplicate
      end

      def validate_candidates(result, packet, accepted)
        candidates = Array(packet.dig(:candidate_review, :candidates))
        result.error('candidate_review.candidates', 'must include candidate evidence') if candidates.empty?
        accepted.each do |uid|
          index = candidates.index { |candidate| candidate[:sli_uid].to_s == uid }
          if index.nil?
            result.error('review.accepted_candidate_uids', "accepted candidate #{uid.inspect} is missing from candidate review")
            next
          end

          validate_candidate(result, candidates.fetch(index), index)
        end
      end

      def validate_candidate(result, candidate, index)
        REQUIRED_CANDIDATE_FIELDS.each do |field|
          validate_presence(result, "candidate_review.candidates[#{index}].#{field}", candidate[field])
        end
        proposed_slo = candidate[:proposed_slo]
        return unless proposed_slo.is_a?(Hash)

        REQUIRED_SLO_FIELDS.each do |field|
          validate_presence(result, "candidate_review.candidates[#{index}].proposed_slo.#{field}", proposed_slo[field])
        end
      end

      def validate_presence(result, path, value)
        return unless value.nil? || value == '' || value == [] || value == {}

        result.error(path, 'is required')
      end
    end
  end
end
