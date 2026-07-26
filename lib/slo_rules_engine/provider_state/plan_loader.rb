# frozen_string_literal: true

module SloRulesEngine
  module ProviderState
    class PlanLoader
      def load(value)
        wrapper, payload = unwrap(value)
        require_hash!('plan', payload)
        require_equal!('schema_version', Value.fetch(payload, :schema_version), SCHEMA_VERSION)
        require_equal!('kind', Value.fetch(payload, :kind), 'ProviderStatePlan')

        provider = required('provider', payload)
        service = required('service', payload)
        mode = required('mode', payload)
        desired_state = load_snapshot(
          'desired_state',
          Value.fetch(payload, :desired_state),
          DesiredState,
          'ProviderDesiredState'
        )
        observed_state = load_snapshot(
          'observed_state',
          Value.fetch(payload, :observed_state),
          ObservedState,
          'ProviderObservedState'
        )
        plan = Plan.new(
          provider: provider,
          service: service,
          mode: mode,
          desired_state: desired_state,
          observed_state: observed_state,
          changes: load_changes(Value.fetch(payload, :changes)),
          findings: load_findings(Value.fetch(payload, :findings), provider: provider),
          summary: load_summary(Value.fetch(payload, :summary))
        )

        require_equal!('fingerprint', Value.fetch(payload, :fingerprint), plan.fingerprint)
        validate_wrapper!(wrapper, plan)
        plan
      end

      private

      def unwrap(value)
        if value.is_a?(Array)
          raise ContractError.new('plan', 'must contain exactly one provider plan') unless value.length == 1

          value = value.first
        end
        require_hash!('plan', value)
        state_contract = Value.fetch(value, :state_contract)
        state_contract ? [value, state_contract] : [nil, value]
      end

      def load_snapshot(path, payload, type, kind)
        require_hash!(path, payload)
        require_equal!("#{path}.schema_version", Value.fetch(payload, :schema_version), SCHEMA_VERSION)
        require_equal!("#{path}.kind", Value.fetch(payload, :kind), kind)
        resources = Value.fetch(payload, :resources)
        require_hash!("#{path}.resources", resources)
        snapshot = type.new(
          provider: required("#{path}.provider", payload, :provider),
          service: required("#{path}.service", payload, :service),
          source: required("#{path}.source", payload, :source),
          resources: resources
        )
        require_equal!("#{path}.fingerprint", Value.fetch(payload, :fingerprint), snapshot.fingerprint)
        snapshot
      end

      def load_changes(payload)
        require_array!('changes', payload)
        payload.each_with_index.map do |change, index|
          path = "changes[#{index}]"
          require_hash!(path, change)
          require_equal!("#{path}.schema_version", Value.fetch(change, :schema_version), SCHEMA_VERSION)
          require_equal!("#{path}.kind", Value.fetch(change, :kind), 'ProviderStateChange')
          Change.new(
            action: required("#{path}.action", change, :action),
            target: required("#{path}.target", change, :target),
            name: required("#{path}.name", change, :name),
            source: required("#{path}.source", change, :source),
            desired: Value.fetch(change, :desired),
            observed: Value.fetch(change, :observed),
            changed_paths: Value.fetch(change, :changed_paths),
            provider_resource_id: Value.fetch(change, :provider_resource_id),
            match_identity: Value.fetch(change, :match_identity),
            risk: Value.fetch(change, :risk)
          )
        end
      end

      def load_findings(payload, provider:)
        require_array!('findings', payload)
        payload.each_with_index.map do |finding, index|
          path = "findings[#{index}]"
          require_hash!(path, finding)
          require_equal!("#{path}.schema_version", Value.fetch(finding, :schema_version), SCHEMA_VERSION)
          require_equal!("#{path}.kind", Value.fetch(finding, :kind), 'ProviderStateFinding')
          Finding.new(
            provider: Value.fetch(finding, :provider) || provider,
            code: required("#{path}.code", finding, :code),
            severity: Value.fetch(finding, :severity) || 'finding',
            message: required("#{path}.message", finding, :message),
            path: Value.fetch(finding, :path),
            target: Value.fetch(finding, :target),
            source: Value.fetch(finding, :source),
            evidence: Value.fetch(finding, :evidence) || {}
          )
        end
      end

      def load_summary(payload)
        require_hash!('summary', payload)
        payload
      end

      def validate_wrapper!(wrapper, plan)
        return unless wrapper

        %i[provider service mode].each do |key|
          value = Value.fetch(wrapper, key)
          next if value.nil?

          require_equal!("wrapper.#{key}", value.to_s, plan.public_send(key))
        end
      end

      def required(path, container, key = nil)
        value = Value.fetch(container, key || path)
        Value.require_presence!(path, value)
        value
      end

      def require_hash!(path, value)
        return if value.is_a?(Hash)

        raise ContractError.new(path, 'must be a hash')
      end

      def require_array!(path, value)
        return if value.is_a?(Array)

        raise ContractError.new(path, 'must be an array')
      end

      def require_equal!(path, actual, expected)
        return if actual == expected

        raise ContractError.new(path, "must equal #{expected.inspect}")
      end
    end
  end
end
