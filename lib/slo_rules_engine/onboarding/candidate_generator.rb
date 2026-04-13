# frozen_string_literal: true

module SloRulesEngine
  module Onboarding
    class CandidateGenerator
      SIGNAL_TO_SLI = {
        'latency' => 'request-latency',
        'errors' => 'request-errors',
        'availability' => 'request-availability',
        'traffic' => 'request-traffic',
        'saturation' => 'resource-saturation',
        'freshness' => 'data-freshness',
        'user_journey' => 'journey-completion'
      }.freeze

      def generate(signals)
        review(signals).fetch(:candidates)
      end

      def review(signals)
        Array(signals).each_with_object(candidates: [], findings: []) do |signal, review|
          kind = signal.fetch(:kind).to_s
          unless SIGNAL_TO_SLI.key?(kind)
            review[:findings] << finding(signal, 'unsupported_signal', "Signal kind #{kind.inspect} is not mapped to a default SLI.")
            next review
          end

          unless signal[:user_visible]
            review[:findings] << finding(signal, 'non_user_visible', 'Telemetry is not user-visible service quality.')
            next review
          end

          if signal[:metric].to_s.empty?
            review[:findings] << finding(signal, 'missing_metric', 'Candidate needs a measured telemetry metric.')
            next review
          end

          review[:candidates] << {
            sli_uid: signal[:sli_uid] || SIGNAL_TO_SLI.fetch(kind),
            signal: kind,
            metric: signal[:metric],
            rationale: signal[:rationale] || 'Measured telemetry is close to user-visible service quality.',
            evidence: evidence(signal),
            calculation_basis_recommendation: calculation_basis_recommendation(signal),
            proposed_slo: {
              uid: signal[:slo_uid] || default_slo_uid(kind),
              objective: signal[:objective] || 0.99,
              success_condition: signal[:success_condition] || default_success_condition(kind),
              calculation_basis: signal[:calculation_basis] || calculation_basis(signal)
            }
          }
        end
      end

      private

      def finding(signal, code, message)
        {
          code: code,
          kind: signal[:kind].to_s,
          metric: signal[:metric],
          message: message
        }.compact
      end

      def default_slo_uid(kind)
        case kind
        when 'latency' then 'fast-enough'
        when 'errors', 'availability' then 'successful-enough'
        when 'freshness' then 'fresh-enough'
        else 'healthy-enough'
        end
      end

      def default_success_condition(kind)
        case kind
        when 'latency' then 'Observation is within a user-reviewed latency threshold.'
        when 'errors', 'availability' then 'Observation completes without service-side failure.'
        when 'freshness' then 'Data age remains within a user-reviewed threshold.'
        else 'Observation meets the reviewed service quality threshold.'
        end
      end

      def calculation_basis(signal)
        recommendation = calculation_basis_recommendation(signal)
        return 'observations' unless recommendation

        recommendation.fetch(:basis)
      end

      def calculation_basis_recommendation(signal)
        return nil unless signal.key?(:observations_per_second) && signal.key?(:failed_observations_to_alert)

        RealityCheck::CalculationBasisAdvisor.new.recommend(
          observations_per_second: signal[:observations_per_second],
          failed_observations_to_alert: signal[:failed_observations_to_alert]
        ).to_h
      end

      def evidence(signal)
        {
          observations_per_second: signal[:observations_per_second],
          failed_observations_to_alert: signal[:failed_observations_to_alert],
          source: signal[:source]
        }.compact
      end
    end
  end
end
