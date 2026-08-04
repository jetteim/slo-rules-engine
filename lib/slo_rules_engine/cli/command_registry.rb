# frozen_string_literal: true

module SloRulesEngine
  module CLI
    class CommandDefinition
      class InvalidDefinition < ArgumentError; end

      SIDE_EFFECT_CLASSES = %w[none local_read local_write provider_read provider_mutation].freeze
      SCHEMA_STATUSES = %w[characterized planned].freeze
      IO_KEYS = %i[local_reads local_writes provider_reads provider_writes credentials].freeze
      OUTPUT_KEYS = %i[stdout persisted_artifacts field_masks streaming].freeze

      attr_reader :id, :version, :human_path, :human_usage, :adapter, :handler, :agent, :schemas,
                  :side_effect, :io, :safety_gates, :output, :mcp

      def initialize(id:, version:, human_path:, human_usage:, adapter:, handler:, agent:, schemas:,
                     side_effect:, io:, safety_gates:, output:, mcp:)
        @id = id
        @version = version
        @human_path = human_path
        @human_usage = human_usage
        @adapter = adapter
        @handler = handler
        @agent = agent
        @schemas = schemas
        @side_effect = side_effect
        @io = io
        @safety_gates = safety_gates
        @output = output
        @mcp = mcp
        validate!
        instance_variables.each { |name| deep_freeze(instance_variable_get(name)) }
        freeze
      end

      def to_h
        {
          id: id,
          version: version,
          human: {
            path: human_path,
            usage: human_usage,
            adapter: adapter
          },
          handler: handler,
          agent: agent,
          schemas: schemas,
          side_effect: side_effect,
          io: io,
          safety_gates: safety_gates,
          output: output,
          mcp: mcp
        }
      end

      private

      def validate!
        invalid!('id is required') unless id.is_a?(String) && id.match?(/\A[a-z][a-z0-9.-]*\z/)
        invalid!('version must be a positive integer') unless version.is_a?(Integer) && version.positive?
        unless human_path.is_a?(Array) && !human_path.empty? && human_path.all? { |part| part.is_a?(String) && !part.empty? }
          invalid!('human_path must contain command tokens')
        end
        invalid!('human_usage must be a bin/rules-ctl command') unless human_usage.to_s.start_with?('bin/rules-ctl ')
        invalid!('adapter must be a method symbol') unless adapter.is_a?(Symbol)
        invalid!('handler must be a method symbol') unless handler.is_a?(Symbol)
        validate_agent!
        validate_schemas!
        invalid!("unsupported side_effect #{side_effect.inspect}") unless SIDE_EFFECT_CLASSES.include?(side_effect)
        validate_exact_keys!(io, IO_KEYS, 'io')
        io.each { |key, values| invalid!("io.#{key} must be an array") unless values.is_a?(Array) }
        unless safety_gates.is_a?(Array) && !safety_gates.empty? && safety_gates.all? { |gate| gate.is_a?(String) && !gate.empty? }
          invalid!('safety_gates must contain at least one gate')
        end
        validate_exact_keys!(output, OUTPUT_KEYS, 'output')
        invalid!('output.stdout is required') if output[:stdout].to_s.empty?
        invalid!('output.persisted_artifacts must be an array') unless output[:persisted_artifacts].is_a?(Array)
        invalid!('output.field_masks is required') if output[:field_masks].to_s.empty?
        invalid!('output.streaming is required') if output[:streaming].to_s.empty?
        validate_exact_keys!(mcp, %i[eligible status tool_id], 'mcp')
        invalid!('mcp.eligible must be boolean') unless [true, false].include?(mcp[:eligible])
        invalid!('mcp.status is required') if mcp[:status].to_s.empty?
        invalid!('mcp.tool_id is required') if mcp[:tool_id].to_s.empty?
      end

      def validate_agent!
        validate_exact_keys!(agent, %i[command_id status invocation request_example], 'agent')
        invalid!('agent.command_id is required') if agent[:command_id].to_s.empty?
        invalid!('agent.command_id must match id') unless agent[:command_id] == id
        invalid!('agent.status is required') if agent[:status].to_s.empty?
        invalid!('agent.invocation is required') if agent[:invocation].to_s.empty?
        validate_exact_keys!(
          agent[:request_example],
          %i[schema_version command_id command_version arguments],
          'agent.request_example'
        )
        invalid!('agent.request_example schema is invalid') unless agent[:request_example][:schema_version] == 'slo-rules-engine/agent-command-request/v1'
        invalid!('agent.request_example command_id must match id') unless agent[:request_example][:command_id] == id
        invalid!('agent.request_example command_version must match version') unless agent[:request_example][:command_version] == version
        invalid!('agent.request_example arguments must be an object') unless agent[:request_example][:arguments].is_a?(Hash)
      end

      def validate_schemas!
        validate_exact_keys!(schemas, %i[request result error], 'schemas')
        schemas.each do |name, schema|
          validate_exact_keys!(schema, %i[ref status], "schemas.#{name}")
          invalid!("schemas.#{name}.ref is required") if schema[:ref].to_s.empty?
          unless SCHEMA_STATUSES.include?(schema[:status])
            invalid!("schemas.#{name}.status must be characterized or planned")
          end
        end
      end

      def validate_exact_keys!(value, expected, path)
        invalid!("#{path} must be an object") unless value.is_a?(Hash)
        actual = value.keys
        return if actual.sort_by(&:to_s) == expected.sort_by(&:to_s)

        invalid!("#{path} keys must be #{expected.join(', ')}")
      end

      def invalid!(message)
        raise InvalidDefinition, "invalid command definition #{id.inspect}: #{message}"
      end

      def deep_freeze(value)
        case value
        when Hash
          value.each { |key, item| deep_freeze(key); deep_freeze(item) }
        when Array
          value.each { |item| deep_freeze(item) }
        end
        value.freeze
      end
    end

    class CommandRegistry
      class InvalidRegistry < ArgumentError; end

      SCHEMA_VERSION = 'slo-rules-engine/cli-command-registry/v1'

      attr_reader :schema_version, :definitions

      def self.default
        @default ||= new(CommandCatalog.definitions)
      end

      def initialize(definitions)
        @schema_version = SCHEMA_VERSION
        @definitions = definitions
        validate!
        @by_id = definitions.each_with_object({}) { |definition, result| result[definition.id] = definition }.freeze
        @by_human_path = definitions.each_with_object({}) do |definition, result|
          result[definition.human_path] = definition
        end.freeze
        @root_handlers = definitions.group_by { |definition| definition.human_path.first }.transform_values do |items|
          items.first.adapter
        end.freeze
        definitions.freeze
        freeze
      end

      def fetch(id)
        @by_id.fetch(id)
      end

      def fetch_human(path)
        @by_human_path.fetch(Array(path))
      end

      def find_human(path)
        @by_human_path[Array(path)]
      end

      def handler_for_human_root(root)
        @root_handlers[root]
      end

      def human_paths
        definitions.map(&:human_path)
      end

      def to_h
        {
          schema_version: schema_version,
          commands: definitions.map(&:to_h)
        }
      end

      private

      def validate!
        raise InvalidRegistry, 'command registry requires at least one command' if definitions.empty?
        unless definitions.all? { |definition| definition.is_a?(CommandDefinition) }
          raise InvalidRegistry, 'command registry entries must be CommandDefinition instances'
        end

        duplicate_id = duplicate_value(definitions.map(&:id))
        raise InvalidRegistry, "duplicate command id #{duplicate_id.inspect}" if duplicate_id

        duplicate_path = duplicate_value(definitions.map(&:human_path))
        if duplicate_path
          raise InvalidRegistry, "duplicate Human CLI path #{duplicate_path.join(' ').inspect}"
        end

        definitions.group_by { |definition| definition.human_path.first }.each do |root, items|
          adapters = items.map(&:adapter).uniq
          next if adapters.length == 1

          raise InvalidRegistry, "Human CLI root #{root.inspect} maps to multiple adapters"
        end
      end

      def duplicate_value(values)
        values.group_by(&:itself).find { |_value, matches| matches.length > 1 }&.first
      end
    end

    module CommandCatalog
      SCHEMA_VERSION = 'slo-rules-engine/cli-command-catalog/v1'
      HUMAN_USAGE = {
        'validate' => 'bin/rules-ctl validate ./service.rb',
        'validate-handoff' => 'bin/rules-ctl validate-handoff ./handoff.json',
        'generate' => 'bin/rules-ctl generate --provider=prometheus_stack --output-dir=./generated ./service.rb',
        'manifest-review' => 'bin/rules-ctl manifest-review --provider=prometheus_stack --manifest=./manifest.json',
        'apply' => 'bin/rules-ctl apply --provider=datadog --dry-run --manifest=./manifest.json',
        'diff' => 'bin/rules-ctl diff --provider=datadog --manifest=./manifest.json',
        'import' => 'bin/rules-ctl import --provider=datadog --manifest=./manifest.json',
        'prune' => 'bin/rules-ctl prune --provider=datadog --dry-run --manifest=./manifest.json',
        'status' => 'bin/rules-ctl status --provider=prometheus_stack --manifest=./manifest.json --base-url=http://localhost:9090',
        'sloth-evidence.capture' => 'bin/rules-ctl sloth-evidence capture --manifest=./manifest.json --input=./sloth.yaml --generated-rules=./rules.yaml --reviewer=reviewer@example.com --reviewed-at=2026-08-04T12:00:00Z --output=./sloth-evidence.json',
        'sloth-evidence.status' => 'bin/rules-ctl sloth-evidence status ./sloth-evidence.json',
        'bundle.create' => 'bin/rules-ctl bundle create --artifact-index=./index.json --reviewer=reviewer@example.com --reviewed-at=2026-08-04T09:00:00Z --output=./bundle.json',
        'bundle.plan' => 'bin/rules-ctl bundle plan ./bundle.json --target-output=checkout/prometheus_stack=./managed --output=./apply-ready.json',
        'bundle.apply' => 'bin/rules-ctl bundle apply ./apply-ready.json --confirm --approved-plan=./approved-plan.json --journal-dir=./journals --output=./applied.json',
        'bundle.verify' => 'bin/rules-ctl bundle verify ./applied.json --output=./verified.json',
        'bundle.status' => 'bin/rules-ctl bundle status ./bundle.json',
        'journal.create' => 'bin/rules-ctl journal create ./provider-plan.json --output=./journal.json',
        'journal.status' => 'bin/rules-ctl journal status ./journal.json',
        'plan.approve' => 'bin/rules-ctl plan approve ./apply-ready.json --target=checkout/prometheus_stack --reviewer=reviewer@example.com --reviewed-at=2026-08-04T09:00:00Z --output=./approved-plan.json',
        'plan.status' => 'bin/rules-ctl plan status ./approved-plan.json',
        'plan.apply' => 'bin/rules-ctl plan apply ./approved-plan.json --confirm --journal-dir=./journals',
        'plan.resume' => 'bin/rules-ctl plan resume ./approved-plan.json --confirm --journal-dir=./journals',
        'lookup-telemetry' => 'bin/rules-ctl lookup-telemetry --provider=prometheus_stack --metric=http_requests_total --base-url=http://localhost:9090',
        'discover-telemetry' => 'bin/rules-ctl discover-telemetry --provider=prometheus_stack --service=checkout --base-url=http://localhost:9090',
        'providers.list' => 'bin/rules-ctl providers list',
        'integrations.list' => 'bin/rules-ctl integrations list',
        'generate-routes' => 'bin/rules-ctl generate-routes --integration=notification_router ./service.rb',
        'candidates' => 'bin/rules-ctl candidates ./telemetry.json',
        'draft-definition' => 'bin/rules-ctl draft-definition --service=checkout --owner=platform ./telemetry.json',
        'draft-from-handoff' => 'bin/rules-ctl draft-from-handoff --service=checkout --owner=platform ./handoff.json',
        'onboarding-summary' => 'bin/rules-ctl onboarding-summary --handoff-dir=./handoffs ./discovery/index.json',
        'onboarding-artifact-index' => 'bin/rules-ctl onboarding-artifact-index --handoff-dir=./handoffs --manifest-dir=./generated --output=./artifact-index.json ./discovery/index.json',
        'review-handoff' => 'bin/rules-ctl review-handoff --accept=request-availability --note=Reviewed ./handoff.json',
        'recommend-calculation-basis' => 'bin/rules-ctl recommend-calculation-basis --observations-per-second=1 --failed-observations-to-alert=5',
        'reality-check' => 'bin/rules-ctl reality-check --provider=prometheus_stack --telemetry=./telemetry.json ./service.rb',
        'migration-report' => 'bin/rules-ctl migration-report ./legacy.rb',
        'model-report' => 'bin/rules-ctl model-report ./service.rb'
      }.freeze
      AGENT_ARGUMENT_EXAMPLES = {
        'validate' => { definition_files: ['./service.rb'] },
        'validate-handoff' => { handoff_file: './handoff.json' },
        'generate' => { provider: 'prometheus_stack', definition_files: ['./service.rb'], output_dir: './generated' },
        'manifest-review' => { provider: 'prometheus_stack', manifest_files: ['./manifest.json'] },
        'apply' => { provider: 'datadog', manifest_file: './manifest.json', mode: 'plan' },
        'diff' => { provider: 'datadog', manifest_file: './manifest.json' },
        'import' => { provider: 'datadog', manifest_file: './manifest.json' },
        'prune' => { provider: 'datadog', manifest_file: './manifest.json', mode: 'plan' },
        'status' => { provider: 'prometheus_stack', manifest_file: './manifest.json', base_url: 'http://localhost:9090' },
        'sloth-evidence.capture' => { manifest_file: './manifest.json', input_files: ['./sloth.yaml'], generated_rules_file: './rules.yaml', reviewer: 'reviewer@example.com', reviewed_at: '2026-08-04T12:00:00Z', output_file: './sloth-evidence.json' },
        'sloth-evidence.status' => { evidence_file: './sloth-evidence.json' },
        'bundle.create' => { artifact_index_file: './index.json', reviewer: 'reviewer@example.com', reviewed_at: '2026-08-04T09:00:00Z', output_file: './bundle.json' },
        'bundle.plan' => { bundle_file: './bundle.json', target_outputs: { 'checkout/prometheus_stack' => './managed' }, output_file: './apply-ready.json' },
        'bundle.apply' => { bundle_file: './apply-ready.json', confirm: true, approved_plan_files: ['./approved-plan.json'], journal_dir: './journals', output_file: './applied.json' },
        'bundle.verify' => { bundle_file: './applied.json', output_file: './verified.json' },
        'bundle.status' => { bundle_file: './bundle.json' },
        'journal.create' => { provider_plan_file: './provider-plan.json', output_file: './journal.json' },
        'journal.status' => { journal_file: './journal.json' },
        'plan.approve' => { bundle_file: './apply-ready.json', target: 'checkout/prometheus_stack', reviewer: 'reviewer@example.com', reviewed_at: '2026-08-04T09:00:00Z', output_file: './approved-plan.json' },
        'plan.status' => { approved_plan_file: './approved-plan.json' },
        'plan.apply' => { approved_plan_file: './approved-plan.json', confirm: true, journal_dir: './journals' },
        'plan.resume' => { approved_plan_file: './approved-plan.json', confirm: true, journal_dir: './journals' },
        'lookup-telemetry' => { provider: 'prometheus_stack', metric: 'http_requests_total', base_url: 'http://localhost:9090' },
        'discover-telemetry' => { provider: 'prometheus_stack', service: 'checkout', base_url: 'http://localhost:9090' },
        'providers.list' => {},
        'integrations.list' => {},
        'generate-routes' => { integration: 'notification_router', definition_files: ['./service.rb'] },
        'candidates' => { telemetry_file: './telemetry.json' },
        'draft-definition' => { service: 'checkout', owner: 'platform', telemetry_file: './telemetry.json' },
        'draft-from-handoff' => { service: 'checkout', owner: 'platform', handoff_file: './handoff.json' },
        'onboarding-summary' => { discovery_index_file: './discovery/index.json', handoff_dir: './handoffs' },
        'onboarding-artifact-index' => { discovery_index_file: './discovery/index.json', handoff_dir: './handoffs', manifest_dir: './generated', output_file: './artifact-index.json' },
        'review-handoff' => { handoff_file: './handoff.json', accept: ['request-availability'], notes: ['Reviewed'] },
        'recommend-calculation-basis' => { observations_per_second: 1, failed_observations_to_alert: 5 },
        'reality-check' => { provider: 'prometheus_stack', telemetry_file: './telemetry.json', definition_files: ['./service.rb'] },
        'migration-report' => { legacy_files: ['./legacy.rb'] },
        'model-report' => { definition_files: ['./service.rb'] }
      }.freeze

      module_function

      def definitions
        @definitions ||= build.freeze
      end

      def to_h
        {
          schema_version: SCHEMA_VERSION,
          commands: definitions.map do |definition|
            {
              id: definition.id,
              human_cli: definition.human_usage,
              agent_cli_json: definition.agent.fetch(:request_example)
            }
          end
        }
      end

      def build
        [
          command('validate', side_effect: 'local_read',
                  io: io(local_reads: %w[definitions]),
                  gates: %w[strict_arguments neutral_model_validation]),
          command('validate-handoff', handler: :validate_handoff, side_effect: 'local_read',
                  io: io(local_reads: %w[handoff_packet]),
                  gates: %w[strict_arguments handoff_schema reviewed_provenance]),
          command('generate', side_effect: 'local_write',
                  io: io(local_reads: %w[definitions handoff_packets],
                         local_writes: %w[provider_manifests manifest_review_report]),
                  gates: %w[strict_arguments neutral_model_validation provider_validation manifest_schema]),
          command('manifest-review', handler: :manifest_review, side_effect: 'local_write',
                  io: io(local_reads: %w[definitions provider_manifests handoff_packets saved_review_report],
                         local_writes: %w[manifest_review_report]),
                  gates: %w[strict_arguments manifest_schema reviewed_provenance evidence_freshness]),
          command('apply', side_effect: 'provider_mutation',
                  io: io(local_reads: %w[definitions provider_manifests handoff_packets saved_review_report operation_journal],
                         local_writes: %w[managed_files operation_journal provider_state_result],
                         provider_reads: %w[provider_state managed_files],
                         provider_writes: %w[provider_state managed_files],
                         credentials: %w[provider_environment_when_live]),
                  gates: %w[strict_arguments reviewed_manifest reviewed_provenance evidence_freshness managed_ownership explicit_confirmation durable_journal post_apply_verification]),
          command('diff', side_effect: 'provider_read',
                  io: io(local_reads: %w[definitions provider_manifests managed_files],
                         provider_reads: %w[provider_state managed_files],
                         credentials: %w[provider_environment_when_live]),
                  gates: %w[strict_arguments provider_validation read_only]),
          command('import', handler: :import_existing, side_effect: 'provider_read',
                  io: io(local_reads: %w[definitions provider_manifests managed_files],
                         provider_reads: %w[provider_state managed_files],
                         credentials: %w[provider_environment_when_live]),
                  gates: %w[strict_arguments provider_validation managed_ownership read_only]),
          command('prune', side_effect: 'provider_mutation',
                  io: io(local_reads: %w[definitions provider_manifests handoff_packets saved_review_report operation_journal],
                         local_writes: %w[managed_files operation_journal provider_state_result],
                         provider_reads: %w[provider_state managed_files],
                         provider_writes: %w[provider_state managed_files],
                         credentials: %w[provider_environment_when_live]),
                  gates: %w[strict_arguments reviewed_manifest reviewed_provenance evidence_freshness managed_ownership explicit_confirmation durable_journal post_apply_verification]),
          command('status', side_effect: 'provider_read',
                  io: io(local_reads: %w[provider_manifest release_bundle live_status_portfolio],
                         local_writes: %w[live_status_report],
                         provider_reads: %w[prometheus_instant_queries]),
                  gates: %w[strict_arguments reviewed_manifest evidence_freshness target_preflight read_only]),
          command('sloth-evidence.capture', path: %w[sloth-evidence capture], side_effect: 'local_write',
                  io: io(local_reads: %w[reviewed_sloth_manifest sloth_native_inputs sloth_generated_rules],
                         local_writes: %w[sloth_downstream_evidence]),
                  gates: %w[strict_arguments reviewed_manifest native_input_parity complete_slo_coverage unambiguous_recording_rules reviewer_attestation credential_scan no_provider_io]),
          command('sloth-evidence.status', path: %w[sloth-evidence status], side_effect: 'local_read',
                  io: io(local_reads: %w[sloth_downstream_evidence reviewed_sloth_manifest sloth_native_inputs sloth_generated_rules]),
                  gates: %w[strict_arguments content_addressed_identity evidence_freshness credential_scan no_provider_io read_only]),

          command('bundle.create', path: %w[bundle create], side_effect: 'local_write',
                  io: io(local_reads: %w[artifact_index provider_plans source_evidence],
                         local_writes: %w[review_ready_bundle]),
                  gates: %w[strict_arguments reviewed_provenance evidence_freshness credential_scan immutable_predecessor]),
          command('bundle.plan', path: %w[bundle plan], side_effect: 'provider_read',
                  io: io(local_reads: %w[review_ready_bundle source_evidence managed_files],
                         local_writes: %w[apply_ready_bundle],
                         provider_reads: %w[provider_state managed_files],
                         credentials: %w[provider_environment_when_live]),
                  gates: %w[strict_arguments evidence_freshness target_runtime_preflight immutable_predecessor no_provider_mutation]),
          command('bundle.apply', path: %w[bundle apply], side_effect: 'local_write',
                  io: io(local_reads: %w[apply_ready_bundle approved_plans source_evidence operation_journals],
                         local_writes: %w[managed_files operation_journals provider_state_results applied_bundle],
                         provider_reads: %w[managed_files],
                         provider_writes: %w[managed_files]),
                  gates: %w[strict_arguments reviewed_provenance evidence_freshness approved_exact_plan explicit_confirmation scope_lock durable_journal post_apply_verification]),
          command('bundle.verify', path: %w[bundle verify], side_effect: 'local_write',
                  io: io(local_reads: %w[applied_bundle approved_plans operation_journals managed_files],
                         local_writes: %w[verified_bundle],
                         provider_reads: %w[managed_files]),
                  gates: %w[strict_arguments evidence_freshness execution_evidence read_only_provider_state immutable_predecessor]),
          command('bundle.status', path: %w[bundle status], side_effect: 'local_read',
                  io: io(local_reads: %w[release_bundle source_evidence]),
                  gates: %w[strict_arguments bundle_schema evidence_freshness read_only]),

          command('journal.create', path: %w[journal create], side_effect: 'local_write',
                  io: io(local_reads: %w[provider_plan], local_writes: %w[operation_journal]),
                  gates: %w[strict_arguments provider_plan_schema credential_scan no_execution]),
          command('journal.status', path: %w[journal status], side_effect: 'local_read',
                  io: io(local_reads: %w[operation_journal]),
                  gates: %w[strict_arguments operation_journal_schema read_only]),

          command('plan.approve', path: %w[plan approve], side_effect: 'local_write',
                  io: io(local_reads: %w[apply_ready_bundle source_evidence provider_plan],
                         local_writes: %w[approved_plan]),
                  gates: %w[strict_arguments reviewed_provenance evidence_freshness reviewer_attestation credential_scan]),
          command('plan.status', path: %w[plan status], side_effect: 'local_read',
                  io: io(local_reads: %w[approved_plan source_evidence managed_files]),
                  gates: %w[strict_arguments approved_plan_schema evidence_freshness managed_path_containment read_only]),
          command('plan.apply', path: %w[plan apply], side_effect: 'local_write',
                  io: io(local_reads: %w[approved_plan source_evidence managed_files operation_journal],
                         local_writes: %w[managed_files operation_journal provider_state_result],
                         provider_reads: %w[managed_files], provider_writes: %w[managed_files]),
                  gates: %w[strict_arguments reviewed_provenance evidence_freshness approved_exact_plan explicit_confirmation scope_lock durable_journal post_apply_verification]),
          command('plan.resume', path: %w[plan resume], side_effect: 'local_write',
                  io: io(local_reads: %w[approved_plan source_evidence managed_files operation_journal],
                         local_writes: %w[managed_files operation_journal provider_state_result],
                         provider_reads: %w[managed_files], provider_writes: %w[managed_files]),
                  gates: %w[strict_arguments approved_exact_plan resumable_journal state_recheck explicit_confirmation scope_lock post_apply_verification]),

          command('lookup-telemetry', handler: :lookup_telemetry, side_effect: 'provider_read',
                  io: io(provider_reads: %w[telemetry_backend],
                         credentials: %w[provider_environment_when_required]),
                  gates: %w[strict_arguments explicit_metric read_only]),
          command('discover-telemetry', handler: :discover_telemetry, side_effect: 'provider_read',
                  io: io(local_reads: %w[scope_file], local_writes: %w[discovery_evidence discovery_index],
                         provider_reads: %w[telemetry_backend],
                         credentials: %w[provider_environment_when_required]),
                  gates: %w[strict_arguments bounded_scope one_provider_per_run read_only_backend]),
          command('providers.list', path: %w[providers list], side_effect: 'none',
                  io: io, gates: %w[offline_only], output: output(streaming: 'not_applicable')),
          command('integrations.list', path: %w[integrations list], side_effect: 'none',
                  io: io, gates: %w[offline_only], output: output(streaming: 'not_applicable')),
          command('generate-routes', handler: :generate_routes, side_effect: 'local_read',
                  io: io(local_reads: %w[definitions]),
                  gates: %w[strict_arguments neutral_model_validation no_delivery_secrets]),
          command('candidates', side_effect: 'local_read',
                  io: io(local_reads: %w[telemetry_evidence]),
                  gates: %w[strict_arguments normalized_telemetry conservative_classification]),
          command('draft-definition', handler: :draft_definition, side_effect: 'local_read',
                  io: io(local_reads: %w[telemetry_evidence]),
                  gates: %w[strict_arguments normalized_telemetry review_required],
                  output: output(stdout: 'ruby', streaming: 'not_applicable')),
          command('draft-from-handoff', handler: :draft_from_handoff, side_effect: 'local_read',
                  io: io(local_reads: %w[handoff_packet]),
                  gates: %w[strict_arguments handoff_schema accepted_candidates reviewed_provenance],
                  output: output(stdout: 'ruby', streaming: 'not_applicable')),
          command('onboarding-summary', handler: :onboarding_summary, side_effect: 'local_write',
                  io: io(local_reads: %w[discovery_index discovery_evidence handoff_packets],
                         local_writes: %w[handoff_packets]),
                  gates: %w[strict_arguments discovery_schema rerun_safe_review_state]),
          command('onboarding-artifact-index', handler: :onboarding_artifact_index, side_effect: 'local_write',
                  io: io(local_reads: %w[discovery_index discovery_evidence handoff_packets reviewed_definitions provider_manifests manifest_review_reports],
                         local_writes: %w[onboarding_artifact_index]),
                  gates: %w[strict_arguments artifact_schema evidence_freshness deterministic_index]),
          command('review-handoff', handler: :review_handoff, side_effect: 'local_write',
                  io: io(local_reads: %w[handoff_packet], local_writes: %w[handoff_packet]),
                  gates: %w[strict_arguments handoff_schema explicit_review_decision preserve_discovery_evidence]),
          command('recommend-calculation-basis', handler: :recommend_calculation_basis, side_effect: 'none',
                  io: io, gates: %w[strict_arguments numeric_bounds], output: output(streaming: 'not_applicable')),
          command('reality-check', handler: :reality_check, side_effect: 'provider_read',
                  io: io(local_reads: %w[definitions telemetry_evidence lookup_results],
                         provider_reads: %w[telemetry_backend],
                         credentials: %w[provider_environment_when_online]),
                  gates: %w[strict_arguments reviewed_provider_binding read_only_backend]),
          command('migration-report', handler: :migration_report, side_effect: 'local_read',
                  io: io(local_reads: %w[legacy_definitions]),
                  gates: %w[strict_arguments public_safe_reporting]),
          command('model-report', handler: :model_report, side_effect: 'local_read',
                  io: io(local_reads: %w[definitions]),
                  gates: %w[strict_arguments neutral_model_validation reviewed_provenance_visibility])
        ]
      end

      def command(id, side_effect:, io:, gates:, path: nil, adapter: nil, handler: nil, output: nil)
        human_path = path || id.split('.')
        handler ||= id.tr('.-', '_').to_sym
        adapter ||= human_path.length == 1 ? handler : human_path.first.tr('-', '_').to_sym
        contract_prefix = "slo-rules-engine/cli-command-contract/#{id}"
        CommandDefinition.new(
          id: id,
          version: 1,
          human_path: human_path,
          human_usage: HUMAN_USAGE.fetch(id),
          adapter: adapter,
          handler: handler,
          agent: {
            command_id: id,
            status: 'planned',
            invocation: "rules-ctl agent invoke #{id}",
            request_example: {
              schema_version: 'slo-rules-engine/agent-command-request/v1',
              command_id: id,
              command_version: 1,
              arguments: AGENT_ARGUMENT_EXAMPLES.fetch(id)
            }
          },
          schemas: {
            request: { ref: "#{contract_prefix}/request/v1", status: 'planned' },
            result: { ref: "#{contract_prefix}/result/v1", status: 'characterized' },
            error: { ref: "#{contract_prefix}/error/v1", status: 'characterized' }
          },
          side_effect: side_effect,
          io: io,
          safety_gates: gates,
          output: output || output(persisted_artifacts: io[:local_writes]),
          mcp: {
            eligible: true,
            status: 'planned',
            tool_id: id.tr('.-', '_')
          }
        )
      end

      def io(local_reads: [], local_writes: [], provider_reads: [], provider_writes: [], credentials: [])
        {
          local_reads: local_reads,
          local_writes: local_writes,
          provider_reads: provider_reads,
          provider_writes: provider_writes,
          credentials: credentials
        }
      end

      def output(stdout: 'json', persisted_artifacts: [], field_masks: 'planned', streaming: 'planned')
        {
          stdout: stdout,
          persisted_artifacts: persisted_artifacts,
          field_masks: field_masks,
          streaming: streaming
        }
      end
    end
  end
end
