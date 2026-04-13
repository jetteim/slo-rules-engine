# frozen_string_literal: true

module SloRulesEngine
  module RealityCheck
    CalculationBasisRecommendation = Struct.new(
      :basis,
      :reason,
      :confidence,
      keyword_init: true
    ) do
      def to_h
        {
          basis: basis,
          reason: reason,
          confidence: confidence
        }
      end
    end

    class CalculationBasisAdvisor
      def recommend(observations_per_second:, failed_observations_to_alert:)
        if observations_per_second.to_f >= 1.0
          CalculationBasisRecommendation.new(
            basis: 'observations',
            confidence: 'high',
            reason: 'Average volume is at least one observation per second.'
          )
        elsif failed_observations_to_alert.to_f < 2.0
          CalculationBasisRecommendation.new(
            basis: 'time_slice',
            confidence: 'high',
            reason: 'One or two failed observations could trigger an alert.'
          )
        else
          CalculationBasisRecommendation.new(
            basis: 'observations',
            confidence: 'medium',
            reason: 'Traffic is in the grey area; start with observations and review sensitivity.'
          )
        end
      end
    end
  end
end
