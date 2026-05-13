# frozen_string_literal: true

module SloRulesEngine
  module Onboarding
    class HandoffReviewer
      class ReviewError < StandardError
        attr_reader :code

        def initialize(code, message)
          @code = code
          super(message)
        end
      end

      def review(path, accepted_candidate_uids: [], rejected_candidate_uids: [], notes: [])
        packet = JSON.parse(File.read(path), symbolize_names: true)
        accepted = normalize_list(accepted_candidate_uids)
        rejected = normalize_list(rejected_candidate_uids)
        note_values = normalize_list(notes)
        validate_review!(packet, accepted, rejected)

        packet[:review] = {
          status: 'reviewed',
          accepted_candidate_uids: accepted,
          rejected_candidate_uids: rejected,
          notes: note_values
        }
        File.write(path, JSON.pretty_generate(packet))
        packet
      end

      private

      def normalize_list(values)
        Array(values).map(&:to_s).map(&:strip).reject(&:empty?).uniq
      end

      def validate_review!(packet, accepted, rejected)
        if accepted.empty? && rejected.empty?
          raise ReviewError.new('missing_review_decision', 'review requires at least one accepted or rejected candidate')
        end

        duplicate = (accepted & rejected).first
        if duplicate
          raise ReviewError.new('conflicting_candidate_decision', "candidate #{duplicate.inspect} cannot be both accepted and rejected")
        end

        known = Array(packet.dig(:candidate_review, :candidates)).map { |candidate| candidate[:sli_uid].to_s }
        unknown = (accepted + rejected).reject { |uid| known.include?(uid) }
        return if unknown.empty?

        raise ReviewError.new('invalid_candidate_uid', "unknown candidate uid(s): #{unknown.join(', ')}")
      end
    end
  end
end
