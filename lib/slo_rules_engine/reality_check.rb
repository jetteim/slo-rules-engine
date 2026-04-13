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

    TelemetryBindingReport = Struct.new(
      :provider,
      :findings,
      keyword_init: true
    ) do
      def initialize(**kwargs)
        super
        self.findings ||= []
      end

      def valid?
        findings.empty?
      end

      def to_h
        {
          provider: provider,
          valid: valid?,
          findings: findings
        }
      end
    end

    class TelemetryBindingChecker
      def initialize(provider:)
        @provider = provider.to_s
      end

      def check(definition, telemetry_signals)
        available_metrics = Array(telemetry_signals).map { |signal| fetch_value(signal, :metric) }.compact
        findings = []

        definition.slis.each do |sli|
          begin
            binding = sli.metric.binding_for(@provider)
          rescue KeyError
            findings << missing_binding_finding(definition, sli)
            next
          end

          unless available_metrics.include?(binding.metric)
            findings << missing_metric_finding(definition, sli, binding.metric)
          end
        end

        TelemetryBindingReport.new(provider: @provider, findings: findings)
      end

      private

      def missing_binding_finding(definition, sli)
        {
          code: 'missing_provider_binding',
          service: definition.service,
          sli: sli.uid,
          provider: @provider
        }
      end

      def missing_metric_finding(definition, sli, metric)
        {
          code: 'missing_provider_metric',
          service: definition.service,
          sli: sli.uid,
          provider: @provider,
          metric: metric
        }
      end

      def fetch_value(hash, key)
        hash[key] || hash[key.to_s]
      end
    end
  end
end
