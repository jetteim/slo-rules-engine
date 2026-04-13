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
        Array(signals).each_with_object([]) do |signal, candidates|
          kind = signal.fetch(:kind).to_s
          next candidates unless SIGNAL_TO_SLI.key?(kind)
          next candidates unless signal[:user_visible]

          candidates << {
            sli_uid: signal[:sli_uid] || SIGNAL_TO_SLI.fetch(kind),
            signal: kind,
            metric: signal[:metric],
            rationale: signal[:rationale] || 'Measured telemetry is close to user-visible service quality.',
            proposed_slo: {
              uid: signal[:slo_uid] || default_slo_uid(kind),
              objective: signal[:objective] || 0.99,
              success_condition: signal[:success_condition] || default_success_condition(kind),
              calculation_basis: signal[:calculation_basis] || 'observations'
            }
          }
        end
      end

      private

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
    end
  end
end
