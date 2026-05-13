# frozen_string_literal: true

module SloRulesEngine
  module Onboarding
    class HandoffDraftGenerator
      class DraftError < StandardError
        attr_reader :code

        def initialize(code, message)
          @code = code
          super(message)
        end
      end

      def initialize(definition_draft_generator: DefinitionDraftGenerator.new, handoff_validator: HandoffValidator.new)
        @definition_draft_generator = definition_draft_generator
        @handoff_validator = handoff_validator
      end

      def generate(path, service:, owner:, environment: 'production')
        packet = JSON.parse(File.read(path), symbolize_names: true)
        review = packet.fetch(:review, {})
        validate_review!(review)
        validation = @handoff_validator.validate(packet, path: path)
        unless validation.valid?
          paths = validation.errors.map(&:path).join(', ')
          raise DraftError.new('invalid_handoff', "handoff packet is not valid for draft generation: #{paths}")
        end

        accepted_candidates = accepted_candidates(packet, review.fetch(:accepted_candidate_uids))
        if accepted_candidates.empty?
          raise DraftError.new('no_accepted_candidates', 'handoff packet has no accepted candidates for draft generation')
        end

        @definition_draft_generator.generate_from_review(
          service: service,
          owner: owner,
          environment: environment,
          review: {
            candidates: accepted_candidates,
            findings: packet.dig(:candidate_review, :findings) || []
          },
          review_notes: review[:notes] || [],
          provenance_comments: provenance_comments(packet),
          review_provenance: review_provenance(packet, review),
          header: '# Generated from reviewed onboarding handoff. Review before production use.'
        )
      end

      private

      def review_provenance(packet, review)
        {
          label: packet[:label],
          provider: packet[:provider],
          accepted_candidate_uids: review[:accepted_candidate_uids] || [],
          rejected_candidate_uids: review[:rejected_candidate_uids] || [],
          notes: review[:notes] || []
        }
      end

      def provenance_comments(packet)
        [
          "handoff: #{packet[:label]} provider=#{packet[:provider]}",
          "handoff scope: #{packet[:scope]}"
        ].compact
      end

      def validate_review!(review)
        return if review[:status].to_s == 'reviewed'

        raise DraftError.new('unreviewed_handoff', 'handoff packet must be reviewed before draft generation')
      end

      def accepted_candidates(packet, accepted_candidate_uids)
        accepted = Array(accepted_candidate_uids).map(&:to_s)
        Array(packet.dig(:candidate_review, :candidates)).select do |candidate|
          accepted.include?(candidate[:sli_uid].to_s)
        end
      end
    end
  end
end
