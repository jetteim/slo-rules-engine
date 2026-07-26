# frozen_string_literal: true

module SloRulesEngine
  module Datadog
    class StateVerifier
      Value = ProviderState::Value
      Fingerprint = ProviderState::Fingerprint

      TARGET_BUCKETS = {
        'datadog.slo' => :slos,
        'datadog.monitor' => :monitors,
        'datadog.dashboard' => :dashboards
      }.freeze

      def initialize(client:, state_planner:, payload_translator:)
        @client = client
        @state_planner = state_planner
        @payload_translator = payload_translator
      end

      def prepare(plan:, journal:)
        resolved_slo_ids = resolved_slo_ids(journal)
        state = if plan.observed_state.source == 'managed_backend_scope'
                  @client.managed_state(service: plan.service)
                else
                  @client.existing_state(
                    desired: @state_planner.desired_state(plan.desired_state.resources)
                  )
                end
        {
          state: state,
          managed: plan.observed_state.source == 'managed_backend_scope',
          resolved_slo_ids: resolved_slo_ids
        }
      rescue StandardError => error
        {
          refresh_error: {
            code: 'backend_state_refresh_failed',
            class: error.class.name,
            message: 'Datadog backend state refresh failed'
          }
        }
      end

      def verify(entry, checked_at:, context:)
        return refresh_failure(entry, checked_at, context.fetch(:refresh_error)) if context[:refresh_error]

        expected = expected_state(entry, context.fetch(:resolved_slo_ids))
        actual = actual_state(entry, context)
        finding = verification_finding(entry, expected, actual)

        {
          status: finding ? 'failed' : 'succeeded',
          checked_at: checked_at,
          path: resource_path(entry),
          expected: expected,
          actual: actual,
          findings: finding ? [finding] : []
        }
      end

      private

      def expected_state(entry, resolved_slo_ids)
        return state(present: false) if Value.fetch(entry, :action) == 'delete'

        payload = @payload_translator.resolve(Value.fetch(entry, :desired), resolved_slo_ids)
        state(
          present: true,
          provider_resource_id: recorded_resource_id(entry),
          payload: @payload_translator.comparable(Value.fetch(entry, :target), payload)
        )
      end

      def actual_state(entry, context)
        backend = backend_entry(entry, context.fetch(:state), managed: context.fetch(:managed))
        return state(present: false) unless backend

        payload = Value.fetch(backend, :payload)
        state(
          present: true,
          provider_resource_id: Value.fetch(backend, :id),
          payload: payload && @payload_translator.comparable(Value.fetch(entry, :target), payload)
        )
      end

      def backend_entry(entry, backend_state, managed:)
        bucket = TARGET_BUCKETS.fetch(Value.fetch(entry, :target))
        resources = Value.fetch(backend_state, bucket) || (managed ? [] : {})
        if managed
          expected_id = recorded_resource_id(entry)
          return Array(resources).find { |resource| Value.fetch(resource, :id).to_s == expected_id.to_s }
        end

        Value.fetch(resources, Value.fetch(entry, :name))
      end

      def state(present:, provider_resource_id: nil, payload: nil)
        identity = { present: present }
        if present
          identity[:provider_resource_id] = provider_resource_id.to_s unless provider_resource_id.nil?
          identity[:payload] = payload unless payload.nil?
        end
        {
          present: present,
          provider_resource_id: provider_resource_id,
          payload_fingerprint: payload && Fingerprint.content(payload),
          fingerprint: Fingerprint.content(identity)
        }.compact
      end

      def verification_finding(entry, expected, actual)
        action = Value.fetch(entry, :action)
        if action == 'delete'
          return unless actual.fetch(:present)

          return finding(
            'backend_resource_present_after_delete',
            'Datadog resource is still present after delete'
          )
        end
        unless actual.fetch(:present)
          return finding(
            'backend_resource_missing_after_apply',
            'Datadog resource is absent after apply'
          )
        end
        if expected[:provider_resource_id] &&
           expected[:provider_resource_id].to_s != actual[:provider_resource_id].to_s
          return finding(
            'backend_resource_identity_mismatch',
            'Datadog resource identity does not match the mutation outcome'
          )
        end
        return if expected.fetch(:fingerprint) == actual.fetch(:fingerprint)

        finding(
          'backend_resource_payload_mismatch',
          'Datadog resource payload does not match the live plan'
        )
      end

      def refresh_failure(entry, checked_at, error)
        expected = Value.fetch(entry, :action) == 'delete' ? state(present: false) : state(present: true)
        actual = state(present: !expected.fetch(:present))
        {
          status: 'failed',
          checked_at: checked_at,
          path: resource_path(entry),
          expected: expected,
          actual: actual,
          findings: [
            finding(error.fetch(:code), error.fetch(:message)).merge(class: error.fetch(:class))
          ]
        }
      end

      def finding(code, message)
        {
          code: code,
          severity: 'error',
          message: message
        }
      end

      def resolved_slo_ids(journal)
        Value.fetch(journal, :entries).each_with_object({}) do |entry, resolved|
          next unless Value.fetch(entry, :target) == 'datadog.slo'

          id = recorded_resource_id(entry)
          resolved[Value.fetch(entry, :name)] = id.to_s if id
        end
      end

      def recorded_resource_id(entry)
        attempt = Value.fetch(entry, :attempts).last
        result = attempt && Value.fetch(attempt, :result)
        Value.fetch(result, :provider_resource_id) || Value.fetch(entry, :provider_resource_id)
      end

      def resource_path(entry)
        "#{Value.fetch(entry, :target)}/#{recorded_resource_id(entry) || Value.fetch(entry, :name)}"
      end
    end
  end
end
