# frozen_string_literal: true

module SloRulesEngine
  module LiveStatus
    class SlothReader < PrometheusReader
      def initialize(
        client_factory: -> { SloRulesEngine::TelemetryLookup::Prometheus::Client.new },
        clock: -> { Time.now.utc },
        max_age_seconds: 300
      )
        @client_factory = client_factory
        super(client: nil, clock: clock, max_age_seconds: max_age_seconds)
      end

      def read(manifest, evidence_path:)
        SloRulesEngine::ManifestSchemaValidator.validate!(manifest)
        provider = fetch_value(manifest, :provider).to_s
        unless provider == 'sloth'
          raise UnsupportedProvider, "Sloth live status is not implemented for provider #{provider.inspect}"
        end

        evidence, evidence_status = SloRulesEngine::Sloth::DownstreamEvidence::StatusEvaluator.new
          .evaluate_with_evidence(evidence_path)
        unless evidence_status.fetch(:fresh)
          raise SloRulesEngine::Sloth::DownstreamEvidence::ContractError,
                evidence_status.fetch(:findings)
        end

        contexts = manifest_contexts(manifest)
        findings = preflight_findings(manifest, evidence, contexts)
        unless findings.empty?
          raise SloRulesEngine::Sloth::DownstreamEvidence::ContractError, findings
        end

        checked_at = @clock.call.utc
        @client = @client_factory.call
        Report.new(
          provider: provider,
          service: fetch_value(manifest, :service),
          checked_at: checked_at.iso8601,
          max_age_seconds: @max_age_seconds,
          review_provenance: fetch_value(manifest, :review_provenance),
          statuses: Array(fetch_value(evidence, :slos)).map do |slo|
            build_sloth_status(evidence, slo, contexts.fetch(fetch_value(slo, :uid)), checked_at)
          end,
          findings: []
        )
      end

      private

      def preflight_findings(manifest, evidence, contexts)
        findings = []
        expected_manifest_fingerprint = fetch_value(fetch_value(evidence, :source, {}), :manifest, {})
          .then { |entry| fetch_value(entry, :fingerprint) }
        actual_manifest_fingerprint = SloRulesEngine::Sloth::DownstreamEvidence::Support.fingerprint(manifest)
        if expected_manifest_fingerprint != actual_manifest_fingerprint
          findings << evidence_finding(
            'sloth_manifest_evidence_mismatch',
            'Sloth live status evidence does not identify the supplied reviewed manifest.',
            expected_fingerprint: expected_manifest_fingerprint,
            actual_fingerprint: actual_manifest_fingerprint
          )
        end

        manifest_service = fetch_value(manifest, :service).to_s
        evidence_service = fetch_value(evidence, :service).to_s
        if manifest_service != evidence_service
          findings << evidence_finding(
            'sloth_evidence_service_mismatch',
            'Sloth live status evidence service does not match the reviewed manifest.',
            manifest_service: manifest_service,
            evidence_service: evidence_service
          )
        end

        manifest_uids = contexts.keys.sort
        evidence_uids = Array(fetch_value(evidence, :slos)).map { |slo| fetch_value(slo, :uid).to_s }.sort
        if manifest_uids != evidence_uids
          findings << evidence_finding(
            'sloth_evidence_slo_coverage_mismatch',
            'Sloth live status evidence must cover every manifest SLO exactly once.',
            missing_uids: manifest_uids - evidence_uids,
            unexpected_uids: evidence_uids - manifest_uids
          )
        end

        contexts.each do |uid, context|
          missing = %i[service sli sli_instance slo].select do |key|
            fetch_value(context.fetch(:identity), key).to_s.empty?
          end
          next if missing.empty?

          findings << evidence_finding(
            'incomplete_sloth_live_status_identity',
            'Sloth manifest alert annotations must retain the complete reviewed SLO identity.',
            uid: uid,
            missing: missing.map(&:to_s)
          )
        end
        Array(fetch_value(evidence, :slos)).each do |slo|
          uid = fetch_value(slo, :uid).to_s
          context = contexts[uid]
          next unless context

          observation_query = fetch_value(
            fetch_value(fetch_value(slo, :status_bindings, {}), :observations, {}),
            :query
          ).to_s
          unless observation_query == context.fetch(:total_query).to_s
            findings << evidence_finding(
              'sloth_evidence_observation_query_mismatch',
              'Sloth observation status binding must match the reviewed native total query.',
              uid: uid
            )
          end
          reviewed_objective = numeric_value(fetch_value(fetch_value(slo, :reviewed_intent, {}), :objective_ratio))
          unless reviewed_objective == context.fetch(:objective_ratio)
            findings << evidence_finding(
              'sloth_evidence_objective_mismatch',
              'Sloth evidence objective must match the reviewed manifest objective.',
              uid: uid,
              manifest_objective_ratio: context.fetch(:objective_ratio),
              evidence_objective_ratio: reviewed_objective
            )
          end
        end
        findings
      end

      def manifest_contexts(manifest)
        artifacts = fetch_value(manifest, :artifacts, {})
        Array(fetch_value(artifacts, :sloth_specs)).each_with_object({}) do |spec, contexts|
          service = fetch_value(spec, :service).to_s
          Array(fetch_value(spec, :slos)).each do |slo|
            name = fetch_value(slo, :name).to_s
            objective_percent = numeric_value(fetch_value(slo, :objective))
            alerting = fetch_value(slo, :alerting, {})
            labels = fetch_value(alerting, :labels, {})
            annotations = fetch_value(alerting, :annotations, {})
            contexts["#{service}/#{name}"] = {
              identity: {
                service: fetch_value(annotations, :service, service),
                sli: fetch_value(annotations, :sli),
                sli_instance: fetch_value(annotations, :sli_instance),
                slo: fetch_value(annotations, :slo)
              },
              context: {
                owner: fetch_value(labels, :owner, fetch_value(fetch_value(spec, :labels, {}), :owner)),
                dashboard: fetch_value(annotations, :dashboard),
                playbook: fetch_value(annotations, :playbook)
              }.compact,
              objective_ratio: objective_percent.nil? ? nil : (objective_percent / 100.0).round(12),
              total_query: fetch_value(
                fetch_value(fetch_value(slo, :sli, {}), :events, {}),
                :total_query
              )
            }
          end
        end
      end

      def build_sloth_status(evidence, slo, context, checked_at)
        findings = []
        provider_evidence = []
        bindings = fetch_value(slo, :status_bindings, {})
        values = %w[
          observations
          success_ratio
          objective_ratio
          error_budget_ratio
          error_budget_remaining_ratio
        ].to_h do |metric|
          binding = fetch_value(bindings, metric.to_sym, {})
          [
            metric,
            query_value(
              fetch_value(binding, :query),
              metric: metric,
              evidence: provider_evidence,
              findings: findings,
              details: { binding_kind: fetch_value(binding, :kind) }
            )
          ]
        end
        burn_windows = Array(fetch_value(bindings, :burn_rate)).map do |binding|
          value = query_value(
            fetch_value(binding, :query),
            metric: 'burn_rate',
            evidence: provider_evidence,
            findings: findings,
            details: { range: fetch_value(binding, :window), binding_kind: fetch_value(binding, :kind) }
          )
          threshold = 1.0
          {
            range: fetch_value(binding, :window),
            value: value,
            threshold: threshold,
            breaching: !value.nil? && !threshold.nil? && value > threshold
          }
        end
        observed_at, age_seconds, fresh = sloth_freshness(
          fetch_value(fetch_value(bindings, :freshness, {}), :query),
          checked_at,
          provider_evidence,
          findings
        )
        intent = fetch_value(slo, :reviewed_intent, {})
        objective = {
          target_ratio: numeric_value(fetch_value(intent, :objective_ratio)),
          provider_target_ratio: values['objective_ratio'],
          evaluation_window: fetch_value(intent, :evaluation_window),
          calculation_basis: 'observations',
          success_ratio: values['success_ratio'],
          attained: objective_attained(values['success_ratio'], fetch_value(intent, :objective_ratio))
        }
        error_budget = error_budget_payload(objective, values)
        append_provider_contract_findings(findings, objective, error_budget)
        state = classify(findings, objective, error_budget, burn_windows)
        append_state_finding(findings, state, objective, error_budget, burn_windows)

        Status.new(
          state: state,
          identity: context.fetch(:identity),
          objective: objective,
          error_budget: error_budget,
          burn_rate: { windows: burn_windows },
          telemetry: {
            observations: values['observations'],
            observed_at: observed_at,
            age_seconds: age_seconds,
            max_age_seconds: @max_age_seconds,
            fresh: fresh
          },
          context: context.fetch(:context),
          provider_resources: provider_resources(evidence, slo),
          provider_evidence: provider_evidence,
          findings: findings
        )
      end

      def sloth_freshness(expression, checked_at, evidence, findings)
        observed_timestamp = query_value(
          expression,
          metric: 'sample_timestamp',
          evidence: evidence,
          findings: findings,
          details: { binding_kind: 'derived_from_recording_rule' }
        )
        return [nil, nil, false] if observed_timestamp.nil?

        observed_at = Time.at(observed_timestamp).utc
        age_seconds = [checked_at.to_f - observed_timestamp, 0.0].max.round(3)
        fresh = age_seconds <= @max_age_seconds
        unless fresh
          findings << Finding.new(
            code: 'stale_live_status_telemetry',
            message: 'Prometheus-compatible SLO status telemetry is older than the allowed freshness boundary.',
            severity: 'warning',
            details: {
              observed_at: observed_at.iso8601,
              age_seconds: age_seconds,
              max_age_seconds: @max_age_seconds
            }
          )
        end
        [observed_at.iso8601, age_seconds, fresh]
      rescue ArgumentError, RangeError
        findings << Finding.new(
          code: 'invalid_live_status_sample',
          message: 'Prometheus-compatible status timestamp is invalid.',
          severity: 'error'
        )
        [nil, nil, false]
      end

      def objective_attained(success_ratio, target_ratio)
        target = numeric_value(target_ratio)
        return nil if success_ratio.nil? || target.nil?

        success_ratio >= target
      end

      def provider_resources(evidence, slo)
        records = fetch_value(slo, :recording_rules, {})
        {
          evidence_id: fetch_value(evidence, :evidence_id),
          sloth_id: fetch_value(fetch_value(slo, :identity, {}), :sloth_id),
          recording_rules: records.to_h.transform_values { |record| fetch_value(record, :selector) }
        }
      end

      def evidence_finding(code, message, details = {})
        SloRulesEngine::Sloth::DownstreamEvidence::Support.finding(code, message, details)
      end
    end
  end
end
