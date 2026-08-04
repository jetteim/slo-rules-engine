# frozen_string_literal: true

require 'json'
require 'time'
require 'yaml'

module SloRulesEngine
  module Sloth
    module DownstreamEvidence
      SCHEMA_VERSION = 'slo-rules-engine/sloth-downstream-evidence/v1'
      KIND = 'SlothDownstreamEvidence'
      STATUS_SCHEMA_VERSION = 'slo-rules-engine/sloth-downstream-evidence-status/v1'
      STATUS_KIND = 'SlothDownstreamEvidenceStatus'
      EVIDENCE_ID_PATTERN = /\Asloth-evidence-[0-9a-f]{64}\z/
      FINGERPRINT_PATTERN = /\A[0-9a-f]{64}\z/
      RECORD_NAME_PATTERN = /\A[a-zA-Z_:][a-zA-Z0-9_:]*\z/
      IDENTITY_LABELS = %w[sloth_id sloth_service sloth_slo].freeze
      STATIC_RECORDS = {
        objective_ratio: 'slo:objective:ratio',
        error_budget_ratio: 'slo:error_budget:ratio',
        time_period_days: 'slo:time_period:days',
        current_burn_rate_ratio: 'slo:current_burn_rate:ratio',
        period_burn_rate_ratio: 'slo:period_burn_rate:ratio',
        error_budget_remaining_ratio: 'slo:period_error_budget_remaining:ratio',
        metadata: 'sloth_slo_info'
      }.freeze
      RECORDING_RULE_ROLES = %i[
        base_error_ratio
        evaluation_error_ratio
        objective_ratio
        error_budget_ratio
        time_period_days
        current_burn_rate_ratio
        period_burn_rate_ratio
        error_budget_remaining_ratio
        metadata
      ].freeze
      STATUS_BINDING_ROLES = %i[
        observations
        success_ratio
        objective_ratio
        error_budget_ratio
        error_budget_remaining_ratio
        burn_rate
        freshness
      ].freeze

      class ContractError < StandardError
        attr_reader :findings

        def initialize(findings)
          @findings = findings
          super('Sloth downstream evidence does not satisfy the reviewed contract')
        end
      end

      module Support
        module_function

        def fetch_value(container, key, default = nil)
          return container[key] if container.is_a?(Hash) && container.key?(key)
          return container[key.to_s] if container.is_a?(Hash) && container.key?(key.to_s)

          default
        end

        def fingerprint(value)
          SloRulesEngine::ReleaseBundle::Fingerprint.content(value)
        end

        def json_file(
          path,
          code: 'unreadable_sloth_manifest',
          message: 'Sloth manifest must be a readable JSON object.'
        )
          JSON.parse(File.read(path))
        rescue Errno::ENOENT, Errno::EACCES, JSON::ParserError => error
          raise ContractError, [finding(
            code,
            message,
            path: path,
            error_class: error.class.name
          )]
        end

        def yaml_documents(path, code: 'unreadable_sloth_yaml')
          documents = YAML.safe_load_stream(
            File.read(path),
            filename: path,
            permitted_classes: [],
            aliases: false
          ).compact
          if documents.empty?
            raise ContractError, [finding(code, 'YAML source must contain at least one document.', path: path)]
          end

          documents
        rescue Errno::ENOENT, Errno::EACCES, Psych::Exception => error
          raise ContractError, [finding(
            code,
            'Sloth YAML source must be readable, safe YAML.',
            path: path,
            error_class: error.class.name
          )]
        end

        def finding(code, message, details = {})
          { code: code, message: message, severity: 'error' }.merge(details)
        end

        def credential_findings(value, path)
          SloRulesEngine::ReleaseBundle::CredentialScanner.paths(value, path).map do |credential_path|
            finding(
              'credential_like_key',
              'Sloth downstream evidence sources must not contain credential-like keys.',
              path: credential_path
            )
          end
        end

        def evidence_identity(evidence)
          identity = JSON.parse(JSON.generate(evidence))
          identity.delete('evidence_id')
          identity
        end

        def evidence_id(evidence)
          "sloth-evidence-#{fingerprint(evidence_identity(evidence))}"
        end
      end

      class Builder
        include Support

        def build(manifest_path:, input_paths:, generated_rules_path:, reviewer:, reviewed_at:)
          findings = validate_attestation(reviewer, reviewed_at)
          manifest = Support.json_file(manifest_path)
          inputs = Array(input_paths).map do |path|
            documents = Support.yaml_documents(path, code: 'unreadable_sloth_native_input')
            if documents.length != 1
              findings << Support.finding(
                'invalid_sloth_native_input_documents',
                'Each Sloth native input file must contain exactly one YAML document.',
                path: path,
                document_count: documents.length
              )
            end
            { path: path, content: documents.fetch(0, nil) }
          end
          generated_documents = Support.yaml_documents(
            generated_rules_path,
            code: 'unreadable_sloth_generated_rules'
          )

          findings.concat(source_credential_findings(manifest, inputs, generated_documents))
          findings.concat(validate_manifest(manifest))
          specs = sloth_specs(manifest)
          findings.concat(validate_native_inputs(specs, inputs))
          expected_slos = expected_slos(specs, inputs, findings)
          rules = generated_rules(generated_documents, findings)
          findings.concat(unrelated_rule_findings(rules, expected_slos))
          slos = expected_slos.map { |expected| build_slo_evidence(expected, rules, findings) }

          raise ContractError, findings unless findings.empty?

          artifact = {
            schema_version: SCHEMA_VERSION,
            kind: KIND,
            provider: 'sloth',
            service: Support.fetch_value(manifest, :service),
            review: {
              reviewer: reviewer.to_s.strip,
              reviewed_at: Time.iso8601(reviewed_at.to_s).utc.iso8601,
              attestation: 'generated rules were reviewed against the linked Sloth manifest and native inputs'
            },
            manifest_review_provenance: Support.fetch_value(manifest, :review_provenance),
            source: {
              manifest: source_entry(manifest_path, manifest),
              native_inputs: inputs.map { |input| source_entry(input.fetch(:path), input.fetch(:content)) },
              generated_rules: source_entry(generated_rules_path, generated_documents)
            },
            generator: {
              name: 'sloth',
              input_schema: 'prometheus/v1',
              output_format: generated_output_format(generated_documents)
            },
            summary: {
              expected_slos: expected_slos.length,
              mapped_slos: slos.length,
              complete: slos.length == expected_slos.length
            },
            slos: slos,
            findings: []
          }
          artifact[:evidence_id] = Support.evidence_id(artifact)
          artifact
        end

        private

        def validate_attestation(reviewer, reviewed_at)
          findings = []
          if reviewer.to_s.strip.empty?
            findings << Support.finding(
              'missing_sloth_evidence_reviewer',
              'A non-empty downstream evidence reviewer identity is required.'
            )
          end
          begin
            Time.iso8601(reviewed_at.to_s)
          rescue ArgumentError
            findings << Support.finding(
              'invalid_sloth_evidence_reviewed_at',
              'The downstream evidence review timestamp must be ISO 8601.'
            )
          end
          findings
        end

        def source_credential_findings(manifest, inputs, generated_documents)
          findings = Support.credential_findings(manifest, 'manifest')
          inputs.each_with_index do |input, index|
            findings.concat(Support.credential_findings(input.fetch(:content), "native_inputs[#{index}]"))
          end
          findings.concat(Support.credential_findings(generated_documents, 'generated_rules'))
          findings
        end

        def validate_manifest(manifest)
          findings = []
          result = SloRulesEngine::ManifestSchemaValidator.validate(manifest)
          result.errors.each do |error|
            findings << Support.finding(
              'invalid_sloth_manifest',
              error.message,
              path: error.path
            )
          end
          unless Support.fetch_value(manifest, :provider).to_s == 'sloth'
            findings << Support.finding(
              'wrong_sloth_evidence_provider',
              'Downstream evidence requires a Sloth provider manifest.',
              provider: Support.fetch_value(manifest, :provider)
            )
          end
          review = SloRulesEngine::ManifestReviewEvidenceValidator.validate([manifest])
          review.errors.each do |error|
            findings << Support.finding(
              'missing_review_provenance',
              error.message,
              path: error.path
            )
          end
          findings
        end

        def sloth_specs(manifest)
          artifacts = Support.fetch_value(manifest, :artifacts, {})
          Array(Support.fetch_value(artifacts, :sloth_specs))
        end

        def validate_native_inputs(specs, inputs)
          findings = []
          if inputs.length != specs.length
            findings << Support.finding(
              'sloth_native_input_count_mismatch',
              'Native input files must cover every reviewed Sloth spec exactly once.',
              expected: specs.length,
              actual: inputs.length
            )
          end
          [specs.length, inputs.length].min.times do |index|
            next if Support.fingerprint(specs.fetch(index)) == Support.fingerprint(inputs.fetch(index).fetch(:content))

            findings << Support.finding(
              'native_input_manifest_mismatch',
              'Native Sloth input does not match its reviewed manifest artifact.',
              path: inputs.fetch(index).fetch(:path),
              manifest_source: "artifacts.sloth_specs[#{index}]"
            )
          end
          findings
        end

        def expected_slos(specs, inputs, findings)
          seen = {}
          specs.each_with_index.flat_map do |spec, spec_index|
            service = Support.fetch_value(spec, :service).to_s
            Array(Support.fetch_value(spec, :slos)).each_with_index.filter_map do |slo, slo_index|
              name = Support.fetch_value(slo, :name).to_s
              uid = "#{service}/#{name}"
              if seen[uid]
                findings << Support.finding(
                  'duplicate_reviewed_sloth_slo',
                  'Reviewed Sloth SLO identities must be unique.',
                  uid: uid
                )
                next
              end
              seen[uid] = true
              {
                uid: uid,
                service: service,
                name: name,
                objective_percent: Support.fetch_value(slo, :objective),
                total_query: Support.fetch_value(Support.fetch_value(Support.fetch_value(slo, :sli, {}), :events, {}), :total_query),
                manifest_source: "artifacts.sloth_specs[#{spec_index}].slos[#{slo_index}]",
                native_input_path: inputs.fetch(spec_index, {}).fetch(:path, nil),
                native_input_source: "slos[#{slo_index}]"
              }
            end
          end
        end

        def generated_rules(documents, findings)
          rules = []
          documents.each_with_index do |document, document_index|
            groups = Support.fetch_value(document, :groups)
            groups ||= Support.fetch_value(Support.fetch_value(document, :spec, {}), :groups)
            unless groups.is_a?(Array)
              findings << Support.finding(
                'invalid_sloth_generated_rule_document',
                'Generated Sloth YAML must contain groups or spec.groups.',
                document: document_index
              )
              next
            end
            groups.each_with_index do |group, group_index|
              group_rules = Support.fetch_value(group, :rules)
              unless group_rules.is_a?(Array)
                findings << Support.finding(
                  'invalid_sloth_generated_rule_group',
                  'Generated Sloth rule groups must contain a rules array.',
                  document: document_index,
                  group: group_index
                )
                next
              end
              group_rules.each_with_index do |rule, rule_index|
                next unless Support.fetch_value(rule, :record)

                rules << {
                  content: rule,
                  source: "documents[#{document_index}].groups[#{group_index}].rules[#{rule_index}]"
                }
              end
            end
          end
          if rules.empty?
            findings << Support.finding(
              'missing_sloth_generated_recording_rules',
              'Generated Sloth YAML must contain recording rules.'
            )
          end
          rules
        end

        def unrelated_rule_findings(rules, expected_slos)
          expected = expected_slos.map { |slo| [slo.fetch(:service), slo.fetch(:name)] }
          rules.filter_map do |rule|
            labels = Support.fetch_value(rule.fetch(:content), :labels, {})
            identity = [Support.fetch_value(labels, :sloth_service).to_s, Support.fetch_value(labels, :sloth_slo).to_s]
            next if expected.include?(identity)

            Support.finding(
              'unrelated_generated_recording_rule',
              'Generated recording rules must belong to a reviewed Sloth SLO in the manifest.',
              source: rule.fetch(:source),
              record: Support.fetch_value(rule.fetch(:content), :record),
              sloth_service: identity.fetch(0),
              sloth_slo: identity.fetch(1)
            )
          end
        end

        def build_slo_evidence(expected, rules, findings)
          matches = rules.select do |rule|
            labels = Support.fetch_value(rule.fetch(:content), :labels, {})
            Support.fetch_value(labels, :sloth_service).to_s == expected.fetch(:service) &&
              Support.fetch_value(labels, :sloth_slo).to_s == expected.fetch(:name)
          end
          static = STATIC_RECORDS.to_h do |role, record|
            [role, unique_rule(matches, record, expected, findings)]
          end
          period_days = parse_period_days(static[:time_period_days], expected, findings)
          ratio_rules = matches.select do |rule|
            Support.fetch_value(rule.fetch(:content), :record).to_s.start_with?('slo:sli_error:ratio_rate')
          end
          evaluation_window = period_days ? "#{period_days}d" : nil
          evaluation = unique_window_rule(ratio_rules, evaluation_window, expected, findings)
          base = shortest_window_rule(ratio_rules, expected, findings)
          all_required = static.values + [evaluation, base]
          sloth_ids = all_required.compact.map do |rule|
            Support.fetch_value(Support.fetch_value(rule.fetch(:content), :labels, {}), :sloth_id).to_s
          end.uniq
          if sloth_ids.length != 1 || sloth_ids.fetch(0, '').empty?
            findings << Support.finding(
              'ambiguous_sloth_generated_identity',
              'Required generated records must share one non-empty sloth_id.',
              uid: expected.fetch(:uid),
              sloth_ids: sloth_ids
            )
          end
          validate_reviewed_values(expected, static, findings)

          records = {
            base_error_ratio: base,
            evaluation_error_ratio: evaluation
          }.merge(static).transform_values { |rule| rule_identity(rule) }
          identity = {
            service: expected.fetch(:service),
            slo: expected.fetch(:name),
            sloth_id: sloth_ids.fetch(0, nil)
          }
          {
            uid: expected.fetch(:uid),
            identity: identity,
            reviewed_intent: {
              objective_ratio: objective_ratio(expected.fetch(:objective_percent)),
              evaluation_window: evaluation_window,
              manifest_source: expected.fetch(:manifest_source),
              native_input_source: {
                path: expected.fetch(:native_input_path),
                source: "#{expected.fetch(:native_input_source)}.sli.events"
              }
            },
            recording_rules: records,
            status_bindings: records.values.all? ? status_bindings(expected, records) : {}
          }
        end

        def unique_rule(rules, record, expected, findings)
          matches = rules.select { |rule| Support.fetch_value(rule.fetch(:content), :record).to_s == record }
          return matches.fetch(0) if matches.length == 1

          code = matches.empty? ? 'missing_generated_recording_rule' : 'ambiguous_generated_recording_rule'
          findings << Support.finding(
            code,
            'Each reviewed Sloth SLO must map to exactly one required generated recording rule.',
            uid: expected.fetch(:uid),
            record: record,
            matches: matches.length
          )
          nil
        end

        def unique_window_rule(rules, window, expected, findings)
          matches = rules.select do |rule|
            labels = Support.fetch_value(rule.fetch(:content), :labels, {})
            Support.fetch_value(labels, :sloth_window).to_s == window.to_s
          end
          return matches.fetch(0) if matches.length == 1

          code = matches.empty? ? 'missing_generated_recording_rule' : 'ambiguous_generated_recording_rule'
          findings << Support.finding(
            code,
            'Each reviewed Sloth SLO must map to one evaluation-window error-ratio record.',
            uid: expected.fetch(:uid),
            role: 'evaluation_error_ratio',
            window: window,
            matches: matches.length
          )
          nil
        end

        def shortest_window_rule(rules, expected, findings)
          ranked = rules.filter_map do |rule|
            labels = Support.fetch_value(rule.fetch(:content), :labels, {})
            seconds = duration_seconds(Support.fetch_value(labels, :sloth_window).to_s)
            [seconds, rule] if seconds
          end.sort_by(&:first)
          if ranked.empty?
            findings << Support.finding(
              'missing_generated_recording_rule',
              'Each reviewed Sloth SLO must map to a base error-ratio recording rule.',
              uid: expected.fetch(:uid),
              role: 'base_error_ratio'
            )
            return nil
          end
          shortest = ranked.take_while { |entry| entry.fetch(0) == ranked.fetch(0).fetch(0) }
          return shortest.fetch(0).fetch(1) if shortest.length == 1

          findings << Support.finding(
            'ambiguous_generated_recording_rule',
            'The base error-ratio recording rule must have one shortest Sloth window.',
            uid: expected.fetch(:uid),
            role: 'base_error_ratio',
            matches: shortest.length
          )
          nil
        end

        def parse_period_days(rule, expected, findings)
          return nil unless rule

          expression = Support.fetch_value(rule.fetch(:content), :expr).to_s.strip
          match = expression.match(/\Avector\(\s*([1-9][0-9]*)\s*\)\z/)
          return Integer(match[1]) if match

          findings << Support.finding(
            'invalid_sloth_time_period_record',
            'Sloth time-period record must be a positive integer-day vector.',
            uid: expected.fetch(:uid),
            expression: expression
          )
          nil
        end

        def validate_reviewed_values(expected, records, findings)
          reviewed = objective_ratio(expected.fetch(:objective_percent))
          objective = vector_number(records[:objective_ratio])
          unless objective && (objective - reviewed).abs <= 1e-9
            findings << Support.finding(
              'sloth_objective_mismatch',
              'Generated Sloth objective record must match reviewed manifest intent.',
              uid: expected.fetch(:uid),
              reviewed: reviewed,
              generated: objective
            )
          end
          budget = vector_budget(records[:error_budget_ratio])
          reviewed_budget = 1.0 - reviewed
          unless budget && (budget - reviewed_budget).abs <= 1e-9
            findings << Support.finding(
              'sloth_error_budget_mismatch',
              'Generated Sloth error-budget record must match reviewed manifest intent.',
              uid: expected.fetch(:uid),
              reviewed: reviewed_budget,
              generated: budget
            )
          end
        end

        def vector_number(rule)
          return nil unless rule

          match = Support.fetch_value(rule.fetch(:content), :expr).to_s.strip.match(
            /\Avector\(\s*([0-9]+(?:\.[0-9]+)?)\s*\)\z/
          )
          Float(match[1]) if match
        rescue ArgumentError
          nil
        end

        def vector_budget(rule)
          return nil unless rule

          expression = Support.fetch_value(rule.fetch(:content), :expr).to_s.strip
          subtraction = expression.match(/\Avector\(\s*1\s*-\s*([0-9]+(?:\.[0-9]+)?)\s*\)\z/)
          return 1.0 - Float(subtraction[1]) if subtraction

          vector_number(rule)
        rescue ArgumentError
          nil
        end

        def objective_ratio(percent)
          (Float(percent) / 100.0).round(12)
        rescue ArgumentError, TypeError
          0.0
        end

        def duration_seconds(value)
          match = value.match(/\A([1-9][0-9]*)([mhd])\z/)
          return nil unless match

          Integer(match[1]) * { 'm' => 60, 'h' => 3600, 'd' => 86_400 }.fetch(match[2])
        end

        def rule_identity(rule)
          return nil unless rule

          content = rule.fetch(:content)
          labels = Support.fetch_value(content, :labels, {})
          {
            record: Support.fetch_value(content, :record),
            labels: JSON.parse(JSON.generate(labels)),
            selector: selector_for(content),
            source: rule.fetch(:source)
          }
        end

        def selector_for(rule)
          record = Support.fetch_value(rule, :record).to_s
          return record unless record.match?(RECORD_NAME_PATTERN)

          labels = Support.fetch_value(rule, :labels, {})
          selected = (IDENTITY_LABELS + ['sloth_window']).filter_map do |key|
            value = Support.fetch_value(labels, key)
            "#{key}=#{JSON.generate(value.to_s)}" unless value.nil?
          end
          selected.empty? ? record : "#{record}{#{selected.join(',')}}"
        end

        def status_bindings(expected, records)
          evaluation = records.fetch(:evaluation_error_ratio)
          {
            observations: {
              kind: 'reviewed_native_input_query',
              query: expected.fetch(:total_query),
              source: "#{expected.fetch(:manifest_source)}.sli.events.total_query"
            },
            success_ratio: derived_binding("1 - (#{evaluation.fetch(:selector)})", evaluation),
            objective_ratio: recorded_binding(records.fetch(:objective_ratio)),
            error_budget_ratio: recorded_binding(records.fetch(:error_budget_ratio)),
            error_budget_remaining_ratio: recorded_binding(records.fetch(:error_budget_remaining_ratio)),
            burn_rate: [
              recorded_binding(records.fetch(:current_burn_rate_ratio)).merge(window: 'current'),
              recorded_binding(records.fetch(:period_burn_rate_ratio)).merge(window: 'evaluation_window')
            ],
            freshness: derived_binding("timestamp(#{evaluation.fetch(:selector)})", evaluation)
          }
        end

        def recorded_binding(record)
          {
            kind: 'recording_rule',
            query: record.fetch(:selector),
            source_record: record.fetch(:record)
          }
        end

        def derived_binding(query, record)
          {
            kind: 'derived_from_recording_rule',
            query: query,
            source_record: record.fetch(:record)
          }
        end

        def source_entry(path, content)
          { path: path, fingerprint: Support.fingerprint(content) }
        end

        def generated_output_format(documents)
          documents.any? { |document| Support.fetch_value(Support.fetch_value(document, :spec, {}), :groups) } ?
            'prometheus_rule_resources' : 'prometheus_rule_groups'
        end
      end

      class SchemaValidator
        def validate(evidence)
          findings = []
          exact(findings, evidence, :schema_version, SCHEMA_VERSION)
          exact(findings, evidence, :kind, KIND)
          exact(findings, evidence, :provider, 'sloth')
          presence(findings, evidence, :service)
          validate_review(findings, Support.fetch_value(evidence, :review))
          validate_manifest_review(findings, Support.fetch_value(evidence, :manifest_review_provenance))
          validate_source(findings, Support.fetch_value(evidence, :source))
          slos = Support.fetch_value(evidence, :slos)
          unless slos.is_a?(Array) && !slos.empty?
            findings << Support.finding('invalid_sloth_evidence_schema', 'slos must be a non-empty array.', path: 'slos')
          end
          validate_slos(findings, Array(slos))
          validate_summary(findings, Support.fetch_value(evidence, :summary), Array(slos).length)
          validate_generator(findings, Support.fetch_value(evidence, :generator))
          unless Support.fetch_value(evidence, :findings) == []
            findings << Support.finding(
              'invalid_sloth_evidence_schema',
              'A persisted complete Sloth evidence artifact must have no findings.',
              path: 'findings'
            )
          end
          findings.concat(Support.credential_findings(evidence, 'evidence'))
          evidence_id = Support.fetch_value(evidence, :evidence_id).to_s
          unless evidence_id.match?(EVIDENCE_ID_PATTERN)
            findings << Support.finding(
              'invalid_sloth_evidence_schema',
              'evidence_id must be a content-addressed Sloth evidence identifier.',
              path: 'evidence_id'
            )
          end
          if evidence_id.match?(EVIDENCE_ID_PATTERN) && evidence_id != Support.evidence_id(evidence)
            findings << Support.finding(
              'sloth_evidence_identity_mismatch',
              'Sloth downstream evidence content does not match its evidence_id.',
              path: 'evidence_id'
            )
          end
          findings
        end

        private

        def exact(findings, container, key, expected)
          return if Support.fetch_value(container, key) == expected

          findings << Support.finding(
            'invalid_sloth_evidence_schema',
            "#{key} must equal #{expected.inspect}.",
            path: key.to_s
          )
        end

        def presence(findings, container, key)
          return unless Support.fetch_value(container, key).to_s.strip.empty?

          findings << Support.finding(
            'invalid_sloth_evidence_schema',
            "#{key} is required.",
            path: key.to_s
          )
        end

        def validate_review(findings, review)
          unless review.is_a?(Hash)
            findings << Support.finding('invalid_sloth_evidence_schema', 'review must be an object.', path: 'review')
            return
          end
          presence(findings, review, :reviewer)
          begin
            Time.iso8601(Support.fetch_value(review, :reviewed_at).to_s)
          rescue ArgumentError
            findings << Support.finding(
              'invalid_sloth_evidence_schema',
              'review.reviewed_at must be ISO 8601.',
              path: 'review.reviewed_at'
            )
          end
        end

        def validate_manifest_review(findings, provenance)
          accepted = Support.fetch_value(provenance, :accepted_candidate_uids)
          return if provenance.is_a?(Hash) && accepted.is_a?(Array) && !accepted.empty?

          findings << Support.finding(
            'invalid_sloth_evidence_schema',
            'manifest_review_provenance must retain accepted reviewed candidates.',
            path: 'manifest_review_provenance.accepted_candidate_uids'
          )
        end

        def validate_source(findings, source)
          unless source.is_a?(Hash)
            findings << Support.finding('invalid_sloth_evidence_schema', 'source must be an object.', path: 'source')
            return
          end
          source_entry(findings, Support.fetch_value(source, :manifest), 'source.manifest')
          inputs = Support.fetch_value(source, :native_inputs)
          unless inputs.is_a?(Array) && !inputs.empty?
            findings << Support.finding(
              'invalid_sloth_evidence_schema',
              'source.native_inputs must be a non-empty array.',
              path: 'source.native_inputs'
            )
          end
          Array(inputs).each_with_index do |input, index|
            source_entry(findings, input, "source.native_inputs[#{index}]")
          end
          source_entry(findings, Support.fetch_value(source, :generated_rules), 'source.generated_rules')
        end

        def source_entry(findings, entry, path)
          unless entry.is_a?(Hash)
            findings << Support.finding('invalid_sloth_evidence_schema', 'source entry must be an object.', path: path)
            return
          end
          if Support.fetch_value(entry, :path).to_s.empty?
            findings << Support.finding('invalid_sloth_evidence_schema', 'source path is required.', path: "#{path}.path")
          end
          unless Support.fetch_value(entry, :fingerprint).to_s.match?(FINGERPRINT_PATTERN)
            findings << Support.finding(
              'invalid_sloth_evidence_schema',
              'source fingerprint must be SHA-256.',
              path: "#{path}.fingerprint"
            )
          end
        end

        def validate_slos(findings, slos)
          seen = {}
          slos.each_with_index do |slo, index|
            path = "slos[#{index}]"
            unless slo.is_a?(Hash)
              findings << invalid_schema('SLO evidence must be an object.', path)
              next
            end
            uid = Support.fetch_value(slo, :uid).to_s
            findings << invalid_schema('SLO uid is required.', "#{path}.uid") if uid.empty?
            if seen[uid]
              findings << invalid_schema('SLO uid must be unique.', "#{path}.uid")
            end
            seen[uid] = true
            validate_slo_identity(findings, Support.fetch_value(slo, :identity), uid, path)
            validate_reviewed_intent(findings, Support.fetch_value(slo, :reviewed_intent), path)
            validate_recording_rules(findings, Support.fetch_value(slo, :recording_rules), path)
            validate_status_bindings(findings, Support.fetch_value(slo, :status_bindings), path)
          end
        end

        def validate_slo_identity(findings, identity, uid, path)
          unless identity.is_a?(Hash)
            findings << invalid_schema('SLO identity must be an object.', "#{path}.identity")
            return
          end
          %i[service slo sloth_id].each do |key|
            if Support.fetch_value(identity, key).to_s.empty?
              findings << invalid_schema("#{key} is required.", "#{path}.identity.#{key}")
            end
          end
          expected_uid = "#{Support.fetch_value(identity, :service)}/#{Support.fetch_value(identity, :slo)}"
          return if uid.empty? || uid == expected_uid

          findings << invalid_schema('SLO uid must match its service/SLO identity.', "#{path}.uid")
        end

        def validate_reviewed_intent(findings, intent, path)
          unless intent.is_a?(Hash)
            findings << invalid_schema('reviewed_intent must be an object.', "#{path}.reviewed_intent")
            return
          end
          objective = Float(Support.fetch_value(intent, :objective_ratio))
          unless objective.positive? && objective <= 1.0
            findings << invalid_schema('objective_ratio must be in (0, 1].', "#{path}.reviewed_intent.objective_ratio")
          end
          unless Support.fetch_value(intent, :evaluation_window).to_s.match?(/\A[1-9][0-9]*d\z/)
            findings << invalid_schema('evaluation_window must be a positive day duration.', "#{path}.reviewed_intent.evaluation_window")
          end
          unless Support.fetch_value(intent, :native_input_source).is_a?(Hash)
            findings << invalid_schema('native_input_source must be an object.', "#{path}.reviewed_intent.native_input_source")
          end
        rescue ArgumentError, TypeError
          findings << invalid_schema('objective_ratio must be numeric.', "#{path}.reviewed_intent.objective_ratio")
        end

        def validate_recording_rules(findings, rules, path)
          unless exact_keys?(rules, RECORDING_RULE_ROLES)
            findings << invalid_schema(
              "recording_rules must contain exactly #{RECORDING_RULE_ROLES.join(', ')}.",
              "#{path}.recording_rules"
            )
            return
          end
          rules.each do |role, record|
            role_name = role.to_sym
            record_path = "#{path}.recording_rules.#{role}"
            unless record.is_a?(Hash)
              findings << invalid_schema('record identity must be an object.', record_path)
              next
            end
            name = Support.fetch_value(record, :record).to_s
            valid_name = if %i[base_error_ratio evaluation_error_ratio].include?(role_name)
                           name.start_with?('slo:sli_error:ratio_rate')
                         else
                           name == STATIC_RECORDS.fetch(role_name)
                         end
            findings << invalid_schema('record name does not match its required role.', "#{record_path}.record") unless valid_name
            %i[labels selector source].each do |key|
              value = Support.fetch_value(record, key)
              invalid = key == :labels ? !value.is_a?(Hash) : value.to_s.empty?
              findings << invalid_schema("#{key} is required.", "#{record_path}.#{key}") if invalid
            end
          end
        end

        def validate_status_bindings(findings, bindings, path)
          unless exact_keys?(bindings, STATUS_BINDING_ROLES)
            findings << invalid_schema(
              "status_bindings must contain exactly #{STATUS_BINDING_ROLES.join(', ')}.",
              "#{path}.status_bindings"
            )
            return
          end
          STATUS_BINDING_ROLES.reject { |role| role == :burn_rate }.each do |role|
            binding = Support.fetch_value(bindings, role)
            unless binding.is_a?(Hash) && !Support.fetch_value(binding, :kind).to_s.empty? &&
                   !Support.fetch_value(binding, :query).to_s.empty?
              findings << invalid_schema('status binding requires kind and query.', "#{path}.status_bindings.#{role}")
            end
          end
          burn = Support.fetch_value(bindings, :burn_rate)
          unless burn.is_a?(Array) && burn.length == 2 && burn.all? do |binding|
            binding.is_a?(Hash) && !Support.fetch_value(binding, :query).to_s.empty? &&
              !Support.fetch_value(binding, :window).to_s.empty?
          end
            findings << invalid_schema(
              'burn_rate must contain current and evaluation-window query bindings.',
              "#{path}.status_bindings.burn_rate"
            )
          end
        end

        def validate_summary(findings, summary, slo_count)
          valid = summary.is_a?(Hash) &&
                  Support.fetch_value(summary, :expected_slos) == slo_count &&
                  Support.fetch_value(summary, :mapped_slos) == slo_count &&
                  Support.fetch_value(summary, :complete) == true
          return if valid

          findings << invalid_schema(
            'summary must report complete expected and mapped SLO coverage.',
            'summary'
          )
        end

        def validate_generator(findings, generator)
          valid = generator.is_a?(Hash) &&
                  Support.fetch_value(generator, :name) == 'sloth' &&
                  Support.fetch_value(generator, :input_schema) == 'prometheus/v1' &&
                  %w[prometheus_rule_groups prometheus_rule_resources].include?(
                    Support.fetch_value(generator, :output_format)
                  )
          return if valid

          findings << invalid_schema('generator metadata is invalid.', 'generator')
        end

        def exact_keys?(value, expected)
          return false unless value.is_a?(Hash)

          value.keys.map(&:to_sym).sort == expected.sort
        end

        def invalid_schema(message, path)
          Support.finding('invalid_sloth_evidence_schema', message, path: path)
        end
      end

      class StatusEvaluator
        def evaluate(evidence_path)
          evidence = Support.json_file(
            evidence_path,
            code: 'unreadable_sloth_downstream_evidence',
            message: 'Sloth downstream evidence must be a readable JSON object.'
          )
          findings = SchemaValidator.new.validate(evidence)
          raise ContractError, findings unless findings.empty?

          source = Support.fetch_value(evidence, :source)
          checks = []
          checks << check_source(Support.fetch_value(source, :manifest), 'manifest') do |path|
            Support.json_file(path)
          end
          Array(Support.fetch_value(source, :native_inputs)).each_with_index do |entry, index|
            checks << check_source(entry, 'native_input', index: index) do |path|
              documents = Support.yaml_documents(path, code: 'unreadable_sloth_native_input')
              raise ContractError, [Support.finding(
                'unreadable_sloth_native_input',
                'Each Sloth native input must still contain exactly one YAML document.',
                path: path
              )] unless documents.length == 1

              documents.fetch(0)
            end
          end
          checks << check_source(Support.fetch_value(source, :generated_rules), 'generated_rules') do |path|
            Support.yaml_documents(path, code: 'unreadable_sloth_generated_rules')
          end
          stale_findings = checks.reject { |check| check.fetch(:fresh) }.map do |check|
            Support.finding(
              stale_code(check.fetch(:kind)),
              'Current Sloth evidence source content does not match the reviewed fingerprint.',
              path: check.fetch(:path),
              expected_fingerprint: check.fetch(:expected_fingerprint),
              actual_fingerprint: check[:actual_fingerprint]
            )
          end
          fresh = stale_findings.empty?
          {
            schema_version: STATUS_SCHEMA_VERSION,
            kind: STATUS_KIND,
            evidence_id: Support.fetch_value(evidence, :evidence_id),
            provider: 'sloth',
            service: Support.fetch_value(evidence, :service),
            status: fresh ? 'fresh' : 'stale',
            fresh: fresh,
            source_checks: checks,
            findings: stale_findings
          }
        end

        private

        def check_source(entry, kind, index: nil)
          path = Support.fetch_value(entry, :path)
          expected = Support.fetch_value(entry, :fingerprint)
          actual = Support.fingerprint(yield(path))
          {
            kind: kind,
            index: index,
            path: path,
            expected_fingerprint: expected,
            actual_fingerprint: actual,
            fresh: expected == actual
          }.compact
        rescue ContractError, Errno::ENOENT, Errno::EACCES, JSON::ParserError, Psych::Exception
          {
            kind: kind,
            index: index,
            path: path,
            expected_fingerprint: expected,
            actual_fingerprint: nil,
            fresh: false
          }.compact
        end

        def stale_code(kind)
          {
            'manifest' => 'stale_sloth_manifest',
            'native_input' => 'stale_sloth_native_input',
            'generated_rules' => 'stale_generated_rules'
          }.fetch(kind)
        end
      end
    end
  end
end
