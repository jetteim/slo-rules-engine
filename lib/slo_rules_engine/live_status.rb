# frozen_string_literal: true

require 'time'

module SloRulesEngine
  module LiveStatus
    SCHEMA_VERSION = 'slo-rules-engine/live-slo-status/v1'
    KIND = 'LiveSLOStatusReport'
    STATES = %w[healthy at_risk exhausted missing_telemetry unverifiable].freeze

    class UnsupportedProvider < StandardError; end

    Finding = Struct.new(:code, :message, :severity, :details, keyword_init: true) do
      def to_h
        {
          code: code,
          message: message,
          severity: severity,
          details: details
        }.compact
      end
    end

    Status = Struct.new(
      :state,
      :identity,
      :objective,
      :error_budget,
      :burn_rate,
      :telemetry,
      :context,
      :provider_resources,
      :provider_evidence,
      :findings,
      keyword_init: true
    ) do
      def to_h
        {
          state: state,
          identity: identity,
          objective: objective,
          error_budget: error_budget,
          burn_rate: burn_rate,
          telemetry: telemetry,
          context: context,
          provider_resources: provider_resources,
          provider_evidence: provider_evidence,
          findings: findings.map(&:to_h)
        }
      end
    end

    Report = Struct.new(
      :provider,
      :service,
      :checked_at,
      :max_age_seconds,
      :review_provenance,
      :statuses,
      :findings,
      keyword_init: true
    ) do
      def initialize(**kwargs)
        super
        self.statuses ||= []
        self.findings ||= []
      end

      def to_h
        {
          schema_version: SCHEMA_VERSION,
          kind: KIND,
          provider: provider,
          service: service,
          checked_at: checked_at,
          max_age_seconds: max_age_seconds,
          review_provenance: review_provenance,
          summary: summary,
          statuses: statuses.map(&:to_h),
          findings: findings.map(&:to_h)
        }.compact
      end

      private

      def summary
        counts = STATES.to_h { |state| [state.to_sym, statuses.count { |status| status.state == state }] }
        { total: statuses.length }.merge(counts)
      end
    end

    class PrometheusReader
      REQUIRED_RECORDING_METRICS = %w[
        observations
        success_ratio
        objective_ratio
        error_budget_ratio
        error_budget_remaining_ratio
      ].freeze
      MISSING_CODES = %w[missing_live_status_metric stale_live_status_telemetry].freeze
      UNVERIFIABLE_CODES = %w[
        incomplete_live_status_manifest
        ambiguous_live_status_metric
        invalid_live_status_sample
        provider_error_budget_mismatch
        provider_objective_mismatch
        provider_status_query_failed
      ].freeze

      def initialize(
        client: SloRulesEngine::TelemetryLookup::Prometheus::Client.new,
        clock: -> { Time.now.utc },
        max_age_seconds: 300
      )
        @client = client
        @clock = clock
        @max_age_seconds = Integer(max_age_seconds)
        raise ArgumentError, 'max_age_seconds must be positive' unless @max_age_seconds.positive?
      end

      def read(manifest)
        SloRulesEngine::ManifestSchemaValidator.validate!(manifest)
        provider = fetch_value(manifest, :provider).to_s
        unless provider == 'prometheus_stack'
          raise UnsupportedProvider, "live status is not implemented for provider #{provider.inspect}"
        end

        checked_at = @clock.call.utc
        artifacts = fetch_value(manifest, :artifacts, {})
        recording_rules = Array(fetch_value(artifacts, :recording_rules, []))
        burn_rules = Array(fetch_value(artifacts, :burn_rate_rules, []))
        success_rules = recording_rules.select { |rule| fetch_value(rule, :metric) == 'success_ratio' }

        report_findings = []
        if success_rules.empty?
          report_findings << Finding.new(
            code: 'incomplete_live_status_manifest',
            message: 'Prometheus Stack manifest has no SLO success-ratio recording rules.',
            severity: 'error'
          )
        end

        Report.new(
          provider: provider,
          service: fetch_value(manifest, :service),
          checked_at: checked_at.iso8601,
          max_age_seconds: @max_age_seconds,
          review_provenance: fetch_value(manifest, :review_provenance),
          statuses: success_rules.map do |success_rule|
            build_status(
              manifest,
              recording_rules,
              burn_rules,
              success_rule,
              checked_at
            )
          end,
          findings: report_findings
        )
      end

      private

      def build_status(manifest, recording_rules, burn_rules, success_rule, checked_at)
        identity = identity_for(success_rule, manifest)
        findings = []
        evidence = []
        records = REQUIRED_RECORDING_METRICS.to_h do |metric|
          rule = find_recording_rule(recording_rules, metric, identity)
          if rule.nil?
            findings << incomplete_rule_finding(metric)
            [metric, nil]
          else
            [metric, fetch_value(rule, :record)]
          end
        end
        matching_burn_rules = burn_rules.select { |rule| identity_matches?(fetch_value(rule, :labels, {}), identity) }
          .sort_by { |rule| fetch_value(rule, :range).to_s }
        if matching_burn_rules.empty?
          findings << incomplete_rule_finding('burn_rate')
        end

        values = {}
        records.each do |metric, expression|
          next if expression.nil?

          values[metric] = query_value(
            expression,
            metric: metric,
            evidence: evidence,
            findings: findings
          )
        end
        burn_windows = matching_burn_rules.map do |rule|
          range = fetch_value(rule, :range).to_s
          value = query_value(
            fetch_value(rule, :record),
            metric: 'burn_rate',
            evidence: evidence,
            findings: findings,
            details: { range: range }
          )
          threshold = numeric_value(fetch_value(rule, :threshold))
          {
            range: range,
            value: value,
            threshold: threshold,
            breaching: !value.nil? && !threshold.nil? && value > threshold
          }
        end

        observed_at, age_seconds, fresh = freshness(
          records['success_ratio'],
          checked_at,
          evidence,
          findings
        )
        objective = objective_payload(success_rule, values)
        error_budget = error_budget_payload(objective, values)
        append_provider_contract_findings(findings, objective, error_budget)
        state = classify(findings, objective, error_budget, burn_windows)
        append_state_finding(findings, state, objective, error_budget, burn_windows)

        Status.new(
          state: state,
          identity: identity,
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
          context: context_for(manifest, identity, success_rule),
          provider_resources: {
            recording_rules: records.values.compact,
            burn_rate_rules: matching_burn_rules.map { |rule| fetch_value(rule, :record) }
          },
          provider_evidence: evidence,
          findings: findings
        )
      end

      def identity_for(rule, manifest)
        labels = fetch_value(rule, :labels, {})
        {
          service: fetch_value(labels, :service, fetch_value(manifest, :service)),
          sli: fetch_value(labels, :sli),
          sli_instance: fetch_value(labels, :sli_instance),
          slo: fetch_value(labels, :slo)
        }
      end

      def find_recording_rule(rules, metric, identity)
        rules.find do |rule|
          next false unless fetch_value(rule, :metric) == metric

          expected = metric == 'observations' ? identity.reject { |key, _value| key == :slo } : identity
          identity_matches?(fetch_value(rule, :labels, {}), expected)
        end
      end

      def identity_matches?(labels, identity)
        identity.all? { |key, value| fetch_value(labels, key).to_s == value.to_s }
      end

      def query_value(expression, metric:, evidence:, findings:, details: nil)
        result = @client.query(expression)
        samples = Array(fetch_value(result, :result, []))
        if samples.empty?
          evidence << evidence_entry(metric, expression, 'missing', details: details)
          findings << Finding.new(
            code: 'missing_live_status_metric',
            message: "Live status metric #{metric.inspect} returned no samples.",
            severity: 'warning',
            details: compact_details(details, expression: expression)
          )
          return nil
        end
        if samples.length != 1
          evidence << evidence_entry(metric, expression, 'ambiguous', details: details)
          findings << Finding.new(
            code: 'ambiguous_live_status_metric',
            message: "Live status metric #{metric.inspect} returned more than one sample.",
            severity: 'error',
            details: compact_details(details, expression: expression, sample_count: samples.length)
          )
          return nil
        end

        sample = samples.fetch(0)
        value_sample = Array(fetch_value(sample, :value))
        value = Float(value_sample.fetch(1))
        raise ArgumentError, 'sample must be finite' unless value.finite?

        evidence << evidence_entry(
          metric,
          expression,
          'ok',
          value: value,
          sample_timestamp: iso8601_timestamp(value_sample.fetch(0)),
          details: details
        )
        value
      rescue KeyError, ArgumentError, TypeError
        evidence << evidence_entry(metric, expression, 'invalid', details: details)
        findings << Finding.new(
          code: 'invalid_live_status_sample',
          message: "Live status metric #{metric.inspect} returned an invalid numeric sample.",
          severity: 'error',
          details: compact_details(details, expression: expression)
        )
        nil
      rescue StandardError => error
        evidence << evidence_entry(metric, expression, 'failed', details: details)
        findings << Finding.new(
          code: 'provider_status_query_failed',
          message: "Prometheus-compatible live status query failed for #{metric.inspect}.",
          severity: 'error',
          details: compact_details(details, expression: expression, error_class: error.class.name)
        )
        nil
      end

      def freshness(success_ratio_record, checked_at, evidence, findings)
        return [nil, nil, false] if success_ratio_record.nil?

        observed_timestamp = query_value(
          "timestamp(#{success_ratio_record})",
          metric: 'sample_timestamp',
          evidence: evidence,
          findings: findings
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

      def objective_payload(success_rule, values)
        labels = fetch_value(success_rule, :labels, {})
        success_ratio = values['success_ratio']
        target_ratio = numeric_value(fetch_value(labels, :objective_ratio))
        {
          target_ratio: target_ratio,
          provider_target_ratio: values['objective_ratio'],
          evaluation_window: fetch_value(labels, :evaluation_window),
          calculation_basis: fetch_value(labels, :calculation_basis),
          success_ratio: success_ratio,
          attained: !success_ratio.nil? && !target_ratio.nil? ? success_ratio >= target_ratio : nil
        }
      end

      def error_budget_payload(objective, values)
        remaining = values['error_budget_remaining_ratio']
        budget_ratio = objective[:target_ratio].nil? ? nil : (1.0 - objective[:target_ratio]).round(12)
        {
          budget_ratio: budget_ratio,
          provider_budget_ratio: values['error_budget_ratio'],
          remaining_ratio: remaining,
          consumed_ratio: remaining.nil? ? nil : (1.0 - remaining).round(12)
        }
      end

      def append_provider_contract_findings(findings, objective, error_budget)
        target = objective[:target_ratio]
        provider_target = objective[:provider_target_ratio]
        if target.nil?
          findings << incomplete_rule_finding('objective_ratio label')
        elsif !provider_target.nil? && (target - provider_target).abs > 1e-12
          findings << Finding.new(
            code: 'provider_objective_mismatch',
            message: 'The live provider objective does not match the reviewed manifest objective.',
            severity: 'error',
            details: {
              reviewed_target_ratio: target,
              provider_target_ratio: provider_target
            }
          )
        end

        budget = error_budget[:budget_ratio]
        provider_budget = error_budget[:provider_budget_ratio]
        return if budget.nil? || provider_budget.nil?
        return if (budget - provider_budget).abs <= 1e-12

        findings << Finding.new(
          code: 'provider_error_budget_mismatch',
          message: 'The live provider error-budget allowance does not match the reviewed manifest objective.',
          severity: 'error',
          details: {
            reviewed_budget_ratio: budget,
            provider_budget_ratio: provider_budget
          }
        )
      end

      def classify(findings, objective, error_budget, burn_windows)
        codes = findings.map(&:code)
        return 'unverifiable' unless (codes & UNVERIFIABLE_CODES).empty?
        return 'missing_telemetry' unless (codes & MISSING_CODES).empty?
        return 'exhausted' if error_budget[:remaining_ratio] <= 0
        return 'at_risk' unless objective[:attained]
        return 'at_risk' if burn_windows.any? { |window| window[:breaching] }

        'healthy'
      end

      def append_state_finding(findings, state, objective, error_budget, burn_windows)
        case state
        when 'exhausted'
          findings << Finding.new(
            code: 'error_budget_exhausted',
            message: 'The SLO error budget is exhausted for the evaluation window.',
            severity: 'critical',
            details: {
              remaining_ratio: error_budget[:remaining_ratio],
              target_ratio: objective[:target_ratio],
              success_ratio: objective[:success_ratio]
            }
          )
        when 'at_risk'
          breached = burn_windows.select { |window| window[:breaching] }
          if breached.any?
            findings << Finding.new(
              code: 'burn_rate_threshold_breached',
              message: 'One or more error-budget burn-rate windows exceed the reviewed threshold.',
              severity: 'warning',
              details: { windows: breached.map { |window| window[:range] } }
            )
          else
            findings << Finding.new(
              code: 'objective_not_attained',
              message: 'The measured success ratio is below the reviewed objective.',
              severity: 'warning'
            )
          end
        end
      end

      def context_for(manifest, identity, success_rule)
        artifacts = fetch_value(manifest, :artifacts, {})
        alert = Array(fetch_value(artifacts, :alert_rules, [])).find do |rule|
          identity_matches?(fetch_value(rule, :labels, {}), identity)
        end
        annotations = fetch_value(alert || {}, :annotations, {})
        labels = fetch_value(success_rule, :labels, {})
        {
          owner: fetch_value(labels, :owner),
          dashboard: fetch_value(annotations, :dashboard),
          playbook: fetch_value(annotations, :playbook)
        }.compact
      end

      def incomplete_rule_finding(metric)
        Finding.new(
          code: 'incomplete_live_status_manifest',
          message: "Prometheus Stack manifest is missing the #{metric.inspect} status rule.",
          severity: 'error',
          details: { metric: metric }
        )
      end

      def evidence_entry(metric, expression, status, value: nil, sample_timestamp: nil, details: nil)
        {
          metric: metric,
          expression: expression,
          status: status,
          value: value,
          sample_timestamp: sample_timestamp,
          details: details
        }.compact
      end

      def compact_details(details, additional = {})
        (details || {}).merge(additional)
      end

      def numeric_value(value)
        numeric = Float(value)
        numeric.finite? ? numeric : nil
      rescue ArgumentError, TypeError
        nil
      end

      def iso8601_timestamp(value)
        Time.at(Float(value)).utc.iso8601
      end

      def fetch_value(container, key, default = nil)
        return default unless container.respond_to?(:fetch)
        return container[key] if container.key?(key)
        return container[key.to_s] if container.key?(key.to_s)

        default
      end
    end
  end
end
