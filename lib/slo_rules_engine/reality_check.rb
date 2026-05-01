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

      def check(definition, telemetry_signals, lookup_results: [])
        normalized_lookup_results = Array(lookup_results)
        signals = Array(telemetry_signals) + lookup_signals(normalized_lookup_results)
        available_metrics = signals.map { |signal| fetch_value(signal, :metric) }.compact
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

          findings.concat(histogram_bucket_findings(definition, sli, binding, available_metrics))
          findings.concat(calculation_basis_findings(definition, sli, binding, signals))
        end

        findings.concat(lookup_findings(normalized_lookup_results))

        TelemetryBindingReport.new(provider: @provider, findings: findings)
      end

      private

      def lookup_signals(lookup_results)
        lookup_results.flat_map { |result| fetch_value(result, :signals, []) }
      end

      def lookup_findings(lookup_results)
        lookup_results.flat_map do |result|
          Array(fetch_value(result, :findings, [])).map { |finding| normalize_finding(finding) }
        end
      end

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

      def histogram_bucket_findings(definition, sli, binding, available_metrics)
        return [] unless %w[prometheus_stack sloth].include?(@provider)
        return [] unless histogram_required?(sli)

        bucket_metric = histogram_bucket_metric(binding.metric)
        return [] if available_metrics.include?(bucket_metric)

        [
          {
            code: 'missing_histogram_bucket',
            service: definition.service,
            sli: sli.uid,
            provider: @provider,
            metric: bucket_metric
          }
        ]
      end

      def calculation_basis_findings(definition, sli, binding, signals)
        matching_signals = signals.select { |signal| fetch_value(signal, :metric) == binding.metric }
        matching_signals.flat_map do |signal|
          volume = fetch_value(signal, :observations_per_second)
          failed_to_alert = fetch_value(signal, :failed_observations_to_alert)
          next [] if volume.nil? || failed_to_alert.nil?

          recommendation = CalculationBasisAdvisor.new.recommend(
            observations_per_second: volume,
            failed_observations_to_alert: failed_to_alert
          )
          sli.instances.flat_map do |instance|
            instance.slos.flat_map do |slo|
              basis = fetch_value(signal, :calculation_basis) || slo.calculation_basis
              calculation_basis_finding(definition, sli, instance, slo, binding.metric, basis, recommendation)
            end
          end
        end
      end

      def calculation_basis_finding(definition, sli, instance, slo, metric, basis, recommendation)
        if recommendation.basis == 'time_slice' && basis != 'time_slice'
          [
            {
              code: 'calculation_basis_low_volume',
              service: definition.service,
              sli: sli.uid,
              sli_instance: instance.uid,
              slo: slo.uid,
              provider: @provider,
              metric: metric,
              current_basis: basis,
              recommended_basis: recommendation.basis,
              reason: recommendation.reason
            }
          ]
        elsif recommendation.basis == 'observations' && basis == 'time_slice'
          [
            {
              code: 'calculation_basis_high_volume',
              service: definition.service,
              sli: sli.uid,
              sli_instance: instance.uid,
              slo: slo.uid,
              provider: @provider,
              metric: metric,
              current_basis: basis,
              recommended_basis: recommendation.basis,
              reason: recommendation.reason
            }
          ]
        else
          []
        end
      end

      def histogram_required?(sli)
        details = sli.measurement_details
        return false unless details

        values = Array(details.threshold_requirements) + Array(details.caveats)
        values.any? { |value| value.to_s.downcase.include?('histogram') }
      end

      def histogram_bucket_metric(metric)
        metric.to_s.sub(/_count\z/, '_bucket')
      end

      def normalize_finding(finding)
        {
          code: fetch_value(finding, :code),
          service: fetch_value(finding, :service),
          sli: fetch_value(finding, :sli),
          provider: fetch_value(finding, :provider) || @provider,
          metric: fetch_value(finding, :metric),
          message: fetch_value(finding, :message),
          details: fetch_value(finding, :details)
        }.compact
      end

      def fetch_value(hash, key, default = nil)
        return hash.public_send(key) if hash.respond_to?(key)
        return default unless hash.respond_to?(:fetch)

        hash.fetch(key) { hash.fetch(key.to_s, default) }
      end
    end
  end
end
