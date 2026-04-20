# frozen_string_literal: true

module SloRulesEngine
  module Appliers
    class Datadog
      ARTIFACTS = [
        {
          collection: :slos,
          state: :slos,
          target: 'datadog.slo',
          source_prefix: 'artifacts.slos',
          create: ['POST', '/api/v1/slo'],
          update: ['PUT', '/api/v1/slo/%<id>s']
        },
        {
          collection: :monitors,
          state: :monitors,
          target: 'datadog.monitor',
          source_prefix: 'artifacts.monitors',
          create: ['POST', '/api/v1/monitor'],
          update: ['PUT', '/api/v1/monitor/%<id>s']
        },
        {
          collection: :telemetry_gap_monitors,
          state: :monitors,
          target: 'datadog.monitor',
          source_prefix: 'artifacts.telemetry_gap_monitors',
          create: ['POST', '/api/v1/monitor'],
          update: ['PUT', '/api/v1/monitor/%<id>s']
        },
        {
          collection: :dashboards,
          state: :dashboards,
          target: 'datadog.dashboard',
          source_prefix: 'artifacts.dashboards',
          create: ['POST', '/api/v1/dashboard'],
          update: ['PUT', '/api/v1/dashboard/%<id>s']
        }
      ].freeze

      def initialize(client: SloRulesEngine::Datadog::Client.new)
        @client = client
      end

      def plan(manifest, mode: 'dry_run')
        state = @client.existing_state
        operations = ARTIFACTS.flat_map do |spec|
          collection(manifest, spec.fetch(:collection)).each_with_index.map do |artifact, index|
            operation_for(manifest, artifact, index, spec, state)
          end
        end

        ApplyPlan.new(provider: 'datadog', mode: mode, operations: operations)
      end

      def apply(manifest)
        @client.validate_credentials!

        plan(manifest, mode: 'live').tap do |apply_plan|
          apply_plan.operations.each do |operation|
            method, path = request_target(operation)
            @client.request(method, path, payload: operation.payload)
          end
        end
      end

      private

      def operation_for(manifest, artifact, index, spec, state)
        source = "#{spec.fetch(:source_prefix)}[#{index}]"
        name = artifact_name(artifact, spec.fetch(:target), index)
        backend_id = backend_id_for(state, spec.fetch(:state), name)
        action = backend_id ? 'update' : 'create'

        ApplyOperation.new(
          action: action,
          target: spec.fetch(:target),
          name: name,
          source: source,
          payload: payload_for(manifest, artifact, spec.fetch(:target), source),
          backend_id: backend_id
        )
      end

      def collection(manifest, key)
        artifacts = fetch_value(manifest, :artifacts, {})
        fetch_value(artifacts, key, [])
      end

      def artifact_name(artifact, target, index)
        fetch_value(artifact, :name) || fetch_value(artifact, :title) || "#{target} #{index + 1}"
      end

      def backend_id_for(state, bucket, name)
        existing = fetch_value(fetch_value(state, bucket, {}), name)
        return unless existing
        return fetch_value(existing, :id) if existing.respond_to?(:fetch)

        existing
      end

      def payload_for(manifest, artifact, target, source)
        {
          source: source,
          provider: 'datadog',
          service: fetch_value(manifest, :service),
          target: target,
          generated_artifact: artifact
        }
      end

      def request_target(operation)
        spec = ARTIFACTS.find { |candidate| candidate.fetch(:target) == operation.target }
        endpoint = operation.action == 'update' ? spec.fetch(:update) : spec.fetch(:create)
        method = endpoint.fetch(0)
        path_template = endpoint.fetch(1)
        [method, format(path_template, id: operation.backend_id)]
      end

      def fetch_value(hash, key, default = nil)
        return default unless hash.respond_to?(:fetch)

        hash.fetch(key) { hash.fetch(key.to_s, default) }
      end
    end
  end
end
