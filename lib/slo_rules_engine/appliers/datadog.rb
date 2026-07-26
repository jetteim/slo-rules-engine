# frozen_string_literal: true

module SloRulesEngine
  module Appliers
    class Datadog
      ARTIFACTS = SloRulesEngine::Datadog::StatePlanner::ARTIFACTS

      def initialize(
        client: SloRulesEngine::Datadog::Client.new,
        risk_policy: SloRulesEngine::Datadog::RiskPolicy.new,
        payload_translator: SloRulesEngine::Datadog::PayloadTranslator.new,
        state_planner: nil
      )
        @client = client
        @risk_policy = risk_policy
        @payload_translator = payload_translator
        @state_planner = state_planner || SloRulesEngine::Datadog::StatePlanner.new(
          risk_policy: @risk_policy,
          payload_translator: @payload_translator
        )
      end

      def plan(manifest, mode: 'dry_run')
        manifest = SloRulesEngine::ManifestSchemaValidator.validate!(manifest)
        desired = @state_planner.desired_state(manifest)
        state = @client.existing_state(desired: desired)
        operations = @state_planner.plan_operations(manifest, state: state)

        apply_plan(manifest, mode: mode, operations: operations, observed: state)
      end

      def diff(manifest)
        manifest = SloRulesEngine::ManifestSchemaValidator.validate!(manifest)
        desired = @state_planner.desired_state(manifest)
        state = @client.existing_state(desired: desired)
        operations = @state_planner.diff_operations(manifest, state: state)

        apply_plan(manifest, mode: 'diff', operations: operations, observed: state)
      end

      def import(manifest)
        manifest = SloRulesEngine::ManifestSchemaValidator.validate!(manifest)
        @client.validate_credentials!
        state = @client.existing_state(desired: @state_planner.desired_state(manifest))
        managed_state = @client.managed_state(service: manifest.fetch(:service))

        ImportedState.new(
          provider: 'datadog',
          service: manifest.fetch(:service),
          source: 'backend_api',
          state: state,
          findings: @state_planner.missing_backend_resource_findings(manifest, state) +
            @state_planner.orphan_backend_resource_findings(manifest, managed_state) +
            @state_planner.weak_identity_match_findings(state),
          desired_state: desired_snapshot(manifest),
          observed_state: observed_snapshot(manifest, state, source: 'backend_api')
        )
      end

      def prune(manifest, mode: 'dry_run')
        manifest = SloRulesEngine::ManifestSchemaValidator.validate!(manifest)
        @client.validate_credentials!
        managed_state = @client.managed_state(service: manifest.fetch(:service))
        operations = @state_planner.prune_operations(manifest, managed_state)

        apply_plan(
          manifest,
          mode: mode,
          operations: operations,
          observed: managed_state,
          observed_source: 'managed_backend_scope'
        ).tap do |plan|
          next unless mode == 'live'

          preflight_live_ownership!(plan.operations)
          plan.operations.each do |operation|
            prune_operation(operation)
          end
        end
      end

      def apply(manifest)
        manifest = SloRulesEngine::ManifestSchemaValidator.validate!(manifest)
        @client.validate_credentials!

        plan(manifest, mode: 'live').tap do |apply_plan|
          preflight_live_ownership!(apply_plan.operations)
          resolved_slo_ids = apply_plan.operations.each_with_object({}) do |operation, resolved|
            next unless operation.target == 'datadog.slo' && operation.backend_id

            resolved[operation.name] = operation.backend_id.to_s
          end
          apply_plan.operations.each do |operation|
            next if operation.action == 'noop'

            response = apply_operation(operation, resolved_slo_ids)
            next unless operation.target == 'datadog.slo'

            generated_id = operation.backend_id || datadog_id_from_response(response)
            resolved_slo_ids[operation.name] = generated_id if generated_id
          end
        end
      end

      private

      def apply_plan(manifest, mode:, operations:, observed:, observed_source: 'backend_api', findings: [])
        ApplyPlan.new(
          provider: 'datadog',
          service: manifest.fetch(:service),
          mode: mode,
          operations: operations,
          findings: findings,
          desired_state: desired_snapshot(manifest),
          observed_state: observed_snapshot(manifest, observed, source: observed_source)
        )
      end

      def desired_snapshot(manifest)
        ProviderState::DesiredState.new(
          provider: 'datadog',
          service: manifest.fetch(:service),
          source: 'provider_manifest',
          resources: manifest
        )
      end

      def observed_snapshot(manifest, state, source:)
        ProviderState::ObservedState.new(
          provider: 'datadog',
          service: manifest.fetch(:service),
          source: source,
          resources: state
        )
      end

      def request_target(operation)
        spec = ARTIFACTS.find { |candidate| candidate.fetch(:target) == operation.target }
        endpoint = case operation.action
                   when 'create', 'create_and_wait', 'recreate', 'recreate_and_wait'
                     spec.fetch(:create)
                   when 'update'
                     spec.fetch(:update)
                   when 'delete'
                     spec.fetch(:delete)
                   else
                     spec.fetch(:create)
                   end
        method = endpoint.fetch(0)
        path_template = endpoint.fetch(1)
        [method, format(path_template, id: operation.backend_id)]
      end

      def apply_operation(operation, resolved_slo_ids)
        payload = resolve_payload(operation.payload, resolved_slo_ids)
        SloRulesEngine::Datadog::PayloadValidator.validate!(operation.target, payload)

        case operation.action
        when 'create_and_wait'
          create_and_wait(operation, payload)
        when 'recreate'
          recreate(operation, payload)
        when 'recreate_and_wait'
          recreate_and_wait(operation, payload)
        else
          method, path = request_target(operation)
          @client.request(method, path, payload: payload)
        end
      end

      def create_and_wait(operation, payload)
        case operation.target
        when 'datadog.slo'
          @client.create_and_wait_slo(payload)
        when 'datadog.monitor'
          @client.create_and_wait_monitor(payload)
        else
          method, path = request_target(operation)
          @client.request(method, path, payload: payload)
        end
      end

      def recreate(operation, payload)
        case operation.target
        when 'datadog.monitor'
          @client.delete_monitor(operation.backend_id)
          @client.request('POST', '/api/v1/monitor', payload: payload)
        when 'datadog.dashboard'
          @client.delete_dashboard(operation.backend_id)
          @client.request('POST', '/api/v1/dashboard', payload: payload)
        else
          raise SloRulesEngine::UnsupportedApplyAction, "unsupported Datadog recreate target #{operation.target.inspect}"
        end
      end

      def recreate_and_wait(operation, payload)
        case operation.target
        when 'datadog.monitor'
          @client.delete_monitor(operation.backend_id)
          @client.create_and_wait_monitor(payload)
        else
          recreate(operation, payload)
        end
      end

      def prune_operation(operation)
        case operation.target
        when 'datadog.slo'
          @client.delete_slo(operation.backend_id, force: true)
        when 'datadog.monitor'
          @client.delete_monitor(operation.backend_id)
        when 'datadog.dashboard'
          @client.delete_dashboard(operation.backend_id)
        else
          raise SloRulesEngine::UnsupportedApplyAction, "unsupported Datadog prune target #{operation.target.inspect}"
        end
      end

      def assert_safe_live_ownership!(operation)
        return unless %w[update recreate recreate_and_wait delete].include?(operation.action)
        return unless weak_match_identity?(operation.match_identity)

        strategy = fetch_value(operation.match_identity, :strategy)
        confidence = fetch_value(operation.match_identity, :confidence)
        result = SloRulesEngine::ValidationResult.new
        result.error(
          'match_identity',
          "live Datadog mutation requires managed source_ref identity for #{operation.action} operations; matched by #{strategy} with #{confidence} confidence"
        )
        raise SloRulesEngine::Datadog::OwnershipError.new(operation: operation, result: result)
      end

      def preflight_live_ownership!(operations)
        operations.each do |operation|
          next if operation.action == 'noop'

          assert_safe_live_ownership!(operation)
        end
      end

      def weak_match_identity?(match_identity)
        return false unless match_identity

        fetch_value(match_identity, :confidence) != 'high'
      end

      def resolve_payload(payload, resolved_slo_ids)
        @payload_translator.resolve(payload, resolved_slo_ids)
      end

      def datadog_id_from_response(response)
        data = fetch_value(response, :data)
        id = case data
             when Array
               fetch_value(data.fetch(0, {}), :id)
             when Hash
               fetch_value(data, :id)
             end

        id || fetch_value(response, :id)
      end

      def fetch_value(hash, key, default = nil)
        return hash.public_send(key) if hash.respond_to?(key)
        return default unless hash.respond_to?(:fetch)

        hash.fetch(key) { hash.fetch(key.to_s, default) }
      end
    end
  end
end
