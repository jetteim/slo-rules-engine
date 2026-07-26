# frozen_string_literal: true

require 'digest'
require 'json'

module SloRulesEngine
  module ProviderState
    SCHEMA_VERSION = 'slo-rules-engine/provider-state/v1'

    class ContractError < StandardError
      attr_reader :path

      def initialize(path, message)
        @path = path
        super("#{path} #{message}")
      end
    end

    module Value
      module_function

      def immutable(value)
        deep_copy(value).tap { |copy| deep_freeze(copy) }
      end

      def copy(value)
        deep_copy(value)
      end

      def compact(hash)
        hash.reject { |_key, value| value.nil? }
      end

      def require_presence!(path, value)
        return unless value.nil? || (value.respond_to?(:empty?) && value.empty?)

        raise ContractError.new(path, 'is required')
      end

      def require_one_of!(path, value, accepted)
        return if accepted.include?(value)

        raise ContractError.new(path, "must be one of #{accepted.inspect}")
      end

      def require_instances!(path, values, type)
        unless values.is_a?(Array)
          raise ContractError.new(path, 'must be an array')
        end
        values.each_with_index do |value, index|
          next if value.is_a?(type)

          raise ContractError.new("#{path}[#{index}]", "must be a #{type.name.split('::').last}")
        end
      end

      def fetch(container, key)
        return container[key] if container.is_a?(Hash) && container.key?(key)
        return nil unless container.is_a?(Hash)

        alternate_key = key.is_a?(String) ? key.to_sym : key.to_s
        return container[alternate_key] if container.key?(alternate_key)

        nil
      end

      def deep_copy(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, entry), copy| copy[deep_copy(key)] = deep_copy(entry) }
        when Array
          value.map { |entry| deep_copy(entry) }
        when String
          value.dup
        else
          value
        end
      end
      private_class_method :deep_copy

      def deep_freeze(value)
        case value
        when Hash
          value.each { |key, entry| deep_freeze(key); deep_freeze(entry) }
        when Array
          value.each { |entry| deep_freeze(entry) }
        end
        value.freeze
      end
      private_class_method :deep_freeze
    end

    module Fingerprint
      module_function

      def content(value)
        Digest::SHA256.hexdigest(JSON.generate(canonicalize(value)))
      end

      def canonicalize(value)
        case value
        when Hash
          value.keys.sort_by(&:to_s).each_with_object({}) do |key, canonical|
            canonical[key.to_s] = canonicalize(value[key])
          end
        when Array
          value.map { |entry| canonicalize(entry) }
        else
          value
        end
      end
    end

    class Snapshot
      attr_reader :provider, :service, :source, :resources, :fingerprint

      def initialize(provider:, service:, source:, resources:)
        Value.require_presence!('provider', provider)
        Value.require_presence!('service', service)
        Value.require_presence!('source', source)

        @provider = provider.to_s.freeze
        @service = service.to_s.freeze
        @source = source.to_s.freeze
        @resources = Value.immutable(resources || {})
        @fingerprint = Fingerprint.content(@resources).freeze
        freeze
      end

      def to_h
        {
          schema_version: SCHEMA_VERSION,
          kind: self.class::KIND,
          provider: provider,
          service: service,
          source: source,
          fingerprint: fingerprint,
          resources: Value.copy(resources)
        }
      end
    end

    class DesiredState < Snapshot
      KIND = 'ProviderDesiredState'
    end

    class ObservedState < Snapshot
      KIND = 'ProviderObservedState'
    end

    class Change
      ACTIONS = %w[
        create
        create_and_wait
        update
        recreate
        recreate_and_wait
        delete
        noop
        write
        handoff
      ].freeze

      attr_reader :action, :target, :name, :source, :desired, :observed,
                  :changed_paths, :provider_resource_id, :match_identity, :risk

      def self.from_apply_operation(operation)
        new(
          action: operation.action,
          target: operation.target,
          name: operation.name,
          source: operation.source,
          desired: operation.payload,
          observed: operation.actual,
          changed_paths: operation.changes,
          provider_resource_id: operation.backend_id,
          match_identity: operation.match_identity,
          risk: operation.risk
        )
      end

      def initialize(
        action:,
        target:,
        name:,
        source:,
        desired: nil,
        observed: nil,
        changed_paths: nil,
        provider_resource_id: nil,
        match_identity: nil,
        risk: nil
      )
        Value.require_one_of!('action', action, ACTIONS)
        Value.require_presence!('target', target)
        Value.require_presence!('name', name)
        Value.require_presence!('source', source)

        @action = action.to_s.freeze
        @target = target.to_s.freeze
        @name = name.to_s.freeze
        @source = source.to_s.freeze
        @desired = Value.immutable(desired)
        @observed = Value.immutable(observed)
        @changed_paths = Value.immutable(Array(changed_paths))
        @provider_resource_id = Value.immutable(provider_resource_id)
        @match_identity = Value.immutable(match_identity)
        @risk = Value.immutable(risk)
        freeze
      end

      def to_h
        Value.compact(
          schema_version: SCHEMA_VERSION,
          kind: 'ProviderStateChange',
          action: action,
          target: target,
          name: name,
          source: source,
          desired: Value.copy(desired),
          observed: Value.copy(observed),
          changed_paths: Value.copy(changed_paths),
          provider_resource_id: Value.copy(provider_resource_id),
          match_identity: Value.copy(match_identity),
          risk: Value.copy(risk)
        )
      end
    end

    class Finding
      SEVERITIES = %w[finding warning error].freeze
      KNOWN_KEYS = %w[provider code severity message path target source evidence].freeze

      attr_reader :provider, :code, :severity, :message, :path, :target, :source, :evidence

      def self.from_hash(value, provider:)
        evidence = value.each_with_object({}) do |(key, entry), details|
          details[key] = entry unless KNOWN_KEYS.include?(key.to_s)
        end
        explicit_evidence = Value.fetch(value, :evidence)
        evidence = explicit_evidence.merge(evidence) if explicit_evidence.is_a?(Hash)
        new(
          provider: Value.fetch(value, :provider) || provider,
          code: Value.fetch(value, :code),
          severity: Value.fetch(value, :severity) || 'finding',
          message: Value.fetch(value, :message),
          path: Value.fetch(value, :path),
          target: Value.fetch(value, :target),
          source: Value.fetch(value, :source),
          evidence: evidence
        )
      end

      def initialize(
        provider:,
        code:,
        message:,
        severity: 'finding',
        path: nil,
        target: nil,
        source: nil,
        evidence: {}
      )
        Value.require_presence!('provider', provider)
        Value.require_presence!('code', code)
        Value.require_presence!('message', message)
        Value.require_one_of!('severity', severity, SEVERITIES)

        @provider = provider.to_s.freeze
        @code = code.to_s.freeze
        @severity = severity.to_s.freeze
        @message = message.to_s.freeze
        @path = path&.to_s&.freeze
        @target = target&.to_s&.freeze
        @source = source&.to_s&.freeze
        @evidence = Value.immutable(evidence || {})
        freeze
      end

      def to_h
        Value.compact(
          schema_version: SCHEMA_VERSION,
          kind: 'ProviderStateFinding',
          provider: provider,
          code: code,
          severity: severity,
          message: message,
          path: path,
          target: target,
          source: source,
          evidence: evidence.empty? ? nil : Value.copy(evidence)
        )
      end
    end

    class Plan
      MODES = %w[dry_run diff live].freeze

      attr_reader :provider, :service, :mode, :desired_state, :observed_state,
                  :changes, :findings, :summary, :fingerprint

      def initialize(
        provider:,
        service:,
        mode:,
        desired_state:,
        observed_state:,
        changes:,
        findings:,
        summary:
      )
        validate_identity!(provider, service, desired_state, observed_state)
        Value.require_one_of!('mode', mode, MODES)
        Value.require_instances!('changes', changes, Change)
        Value.require_instances!('findings', findings, Finding)
        findings.each_with_index do |finding, index|
          next if finding.provider == provider.to_s

          raise ContractError.new("findings[#{index}].provider", 'must match plan provider')
        end

        @provider = provider.to_s.freeze
        @service = service.to_s.freeze
        @mode = mode.to_s.freeze
        @desired_state = desired_state
        @observed_state = observed_state
        @changes = Value.immutable(changes)
        @findings = Value.immutable(findings)
        @summary = Value.immutable(summary)
        @fingerprint = Fingerprint.content(identity_payload).freeze
        freeze
      end

      def to_h
        {
          schema_version: SCHEMA_VERSION,
          kind: 'ProviderStatePlan',
          provider: provider,
          service: service,
          mode: mode,
          fingerprint: fingerprint,
          desired_state: desired_state.to_h,
          observed_state: observed_state.to_h,
          changes: changes.map(&:to_h),
          findings: findings.map(&:to_h),
          summary: Value.copy(summary)
        }
      end

      private

      def identity_payload
        {
          provider: provider,
          service: service,
          mode: mode,
          desired_state_fingerprint: desired_state.fingerprint,
          observed_state_fingerprint: observed_state.fingerprint,
          changes: changes.map(&:to_h),
          findings: findings.map(&:to_h),
          summary: summary
        }
      end

      def validate_identity!(provider, service, desired_state, observed_state)
        Value.require_presence!('provider', provider)
        Value.require_presence!('service', service)
        unless desired_state.is_a?(DesiredState)
          raise ContractError.new('desired_state', 'must be a ProviderDesiredState')
        end
        unless observed_state.is_a?(ObservedState)
          raise ContractError.new('observed_state', 'must be a ProviderObservedState')
        end
        [desired_state, observed_state].each do |snapshot|
          raise ContractError.new('provider', 'must match state snapshots') unless snapshot.provider == provider.to_s
          raise ContractError.new('service', 'must match state snapshots') unless snapshot.service == service.to_s
        end
      end
    end

    class Import
      attr_reader :provider, :service, :desired_state, :observed_state, :findings, :fingerprint

      def initialize(provider:, service:, desired_state:, observed_state:, findings:)
        validate_identity!(provider, service, desired_state, observed_state)
        Value.require_instances!('findings', findings, Finding)

        @provider = provider.to_s.freeze
        @service = service.to_s.freeze
        @desired_state = desired_state
        @observed_state = observed_state
        @findings = Value.immutable(findings)
        @fingerprint = Fingerprint.content(identity_payload).freeze
        freeze
      end

      def to_h
        {
          schema_version: SCHEMA_VERSION,
          kind: 'ProviderStateImport',
          provider: provider,
          service: service,
          fingerprint: fingerprint,
          desired_state: desired_state.to_h,
          observed_state: observed_state.to_h,
          findings: findings.map(&:to_h)
        }
      end

      private

      def identity_payload
        {
          provider: provider,
          service: service,
          desired_state_fingerprint: desired_state.fingerprint,
          observed_state_fingerprint: observed_state.fingerprint,
          findings: findings.map(&:to_h)
        }
      end

      def validate_identity!(provider, service, desired_state, observed_state)
        Value.require_presence!('provider', provider)
        Value.require_presence!('service', service)
        unless desired_state.is_a?(DesiredState)
          raise ContractError.new('desired_state', 'must be a ProviderDesiredState')
        end
        unless observed_state.is_a?(ObservedState)
          raise ContractError.new('observed_state', 'must be a ProviderObservedState')
        end
        [desired_state, observed_state].each do |snapshot|
          raise ContractError.new('provider', 'must match state snapshots') unless snapshot.provider == provider.to_s
          raise ContractError.new('service', 'must match state snapshots') unless snapshot.service == service.to_s
        end
      end
    end

    class Result
      STATUSES = %w[succeeded partial failed noop blocked].freeze

      attr_reader :provider, :service, :mode, :status, :desired_state_fingerprint,
                  :observed_state_fingerprint, :plan_fingerprint, :operation_results,
                  :findings, :verification

      def initialize(
        provider:,
        service:,
        mode:,
        status:,
        desired_state_fingerprint:,
        observed_state_fingerprint:,
        plan_fingerprint:,
        operation_results:,
        findings:,
        verification:
      )
        Value.require_presence!('provider', provider)
        Value.require_presence!('service', service)
        Value.require_presence!('mode', mode)
        Value.require_one_of!('status', status, STATUSES)
        validate_fingerprint!('desired_state_fingerprint', desired_state_fingerprint)
        validate_fingerprint!('observed_state_fingerprint', observed_state_fingerprint)
        validate_fingerprint!('plan_fingerprint', plan_fingerprint)
        Value.require_instances!('findings', findings, Finding)
        unless verification.is_a?(Hash)
          raise ContractError.new('verification', 'must be a hash')
        end

        @provider = provider.to_s.freeze
        @service = service.to_s.freeze
        @mode = mode.to_s.freeze
        @status = status.to_s.freeze
        @desired_state_fingerprint = desired_state_fingerprint.to_s.freeze
        @observed_state_fingerprint = observed_state_fingerprint.to_s.freeze
        @plan_fingerprint = plan_fingerprint.to_s.freeze
        @operation_results = Value.immutable(Array(operation_results))
        @findings = Value.immutable(Array(findings))
        @verification = Value.immutable(verification || {})
        freeze
      end

      def to_h
        {
          schema_version: SCHEMA_VERSION,
          kind: 'ProviderStateResult',
          provider: provider,
          service: service,
          mode: mode,
          status: status,
          desired_state_fingerprint: desired_state_fingerprint,
          observed_state_fingerprint: observed_state_fingerprint,
          plan_fingerprint: plan_fingerprint,
          operation_results: Value.copy(operation_results),
          findings: findings.map(&:to_h),
          verification: Value.copy(verification)
        }
      end

      private

      def validate_fingerprint!(path, value)
        return if value.to_s.match?(/\A[0-9a-f]{64}\z/)

        raise ContractError.new(path, 'must be a SHA-256 fingerprint')
      end
    end
  end
end
