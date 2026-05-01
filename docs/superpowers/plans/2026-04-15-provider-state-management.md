# Provider State Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add provider-state management so reviewed SLO artifacts can be planned, dry-run applied, and eventually reconciled with backend state through provider-specific modes.

**Architecture:** Keep `generate` deterministic and read-only. Model backend management as an observability state pipeline: sources become normalized evidence, transforms produce validation findings and apply plans, and sinks perform file writes, external-generator handoff, or confirmed backend API calls. Datadog gets live API support first; Prometheus-compatible and Sloth providers participate through explicit manifest and external-generator modes.

**Tech Stack:** Ruby, Minitest, standard library JSON/FileUtils/Net::HTTP, existing `rules-ctl` CLI.

---

## File Structure

- Modify `lib/slo_rules_engine/provider.rb`: add `automation_mode`, `state_actions`, and default unsupported state behavior.
- Create `lib/slo_rules_engine/apply.rb`: define `ApplyOperation`, `ApplyPlan`, `ApplyResult`, and `UnsupportedApplyAction`.
- Create `lib/slo_rules_engine/appliers/manifest_bundle.rb`: writes generated manifests through apply planning for file-backed providers.
- Create `lib/slo_rules_engine/appliers/datadog.rb`: maps Datadog generated artifacts to API operations.
- Create `lib/slo_rules_engine/datadog/client.rb`: injectable Datadog HTTP client with credential checks and retry handling.
- Create `lib/slo_rules_engine/telemetry_lookup.rb`: normalized lookup request/result objects.
- Create `lib/slo_rules_engine/telemetry_lookup/datadog.rb`: Datadog lookup adapter.
- Create `lib/slo_rules_engine/telemetry_lookup/prometheus.rb`: Prometheus-compatible lookup adapter.
- Modify `lib/slo_rules_engine.rb`: require and register new components.
- Modify `bin/rules-ctl`: add `apply`, `lookup-telemetry`, and online sanity-check options without changing `generate`.
- Modify `README.md`, `docs/features.md`, `docs/evolution-plan.md`, `docs/provider-contract.md`, and `docs/provider-contribution-guide.md`.
- Add tests in `test/providers_test.rb`, `test/apply_test.rb`, `test/datadog_apply_test.rb`, `test/telemetry_lookup_test.rb`, and `test/cli_test.rb`.

## Pipeline Test Rules

- Source fixtures must be public-safe service definitions, telemetry inventories, generated manifests, or fake backend state.
- Transform tests assert deterministic outputs: candidate lists, findings, apply operations, and unsupported-action errors.
- Sink tests use fake clients or temporary directories.
- No test may contact Datadog, Prometheus, Kubernetes, Grafana, Alertmanager, or Sloth.
- Every provider apply path must expose dry-run output before live mutation is implemented.

## Task 1: Provider Automation Metadata

**Files:**
- Modify: `lib/slo_rules_engine/provider.rb`
- Modify: `lib/slo_rules_engine/providers/datadog.rb`
- Modify: `lib/slo_rules_engine/providers/prometheus_stack.rb`
- Modify: `lib/slo_rules_engine/providers/sloth.rb`
- Modify: `bin/rules-ctl`
- Test: `test/providers_test.rb`

- [ ] **Step 1: Write the failing provider metadata test**

Add to `test/providers_test.rb`:

```ruby
def test_provider_registry_lists_automation_modes_and_state_actions
  providers = SloRulesEngine.default_provider_registry.list.to_h do |provider|
    [provider.key, { automation_mode: provider.automation_mode, state_actions: provider.state_actions }]
  end

  assert_equal 'live_api', providers.fetch('datadog').fetch(:automation_mode)
  assert_includes providers.fetch('datadog').fetch(:state_actions), 'apply'
  assert_equal 'manifest_bundle', providers.fetch('prometheus_stack').fetch(:automation_mode)
  assert_includes providers.fetch('prometheus_stack').fetch(:state_actions), 'apply'
  assert_equal 'external_generator', providers.fetch('sloth').fetch(:automation_mode)
  assert_includes providers.fetch('sloth').fetch(:state_actions), 'apply'
end
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `ruby -Ilib test/providers_test.rb`

Expected: failure because `automation_mode` is not defined.

- [ ] **Step 3: Implement provider metadata**

Change `Provider` initializer to this shape:

```ruby
attr_reader :key, :capabilities, :automation_mode, :state_actions

def initialize(key:, capabilities:, automation_mode: 'manifest_only', state_actions: [])
  @key = key
  @capabilities = capabilities
  @automation_mode = automation_mode
  @state_actions = state_actions
end
```

Set provider metadata:

```ruby
# datadog
automation_mode: 'live_api',
state_actions: %w[plan apply]

# prometheus_stack
automation_mode: 'manifest_bundle',
state_actions: %w[plan apply]

# sloth
automation_mode: 'external_generator',
state_actions: %w[plan apply]
```

- [ ] **Step 4: Include metadata in CLI provider listing**

In `bin/rules-ctl`, change provider listing entries to:

```ruby
{
  key: provider.key,
  capabilities: provider.capabilities,
  automation_mode: provider.automation_mode,
  state_actions: provider.state_actions
}
```

- [ ] **Step 5: Run tests and commit**

Run:

```bash
ruby -Ilib test/providers_test.rb
ruby -Ilib test/cli_test.rb
```

Expected: both commands exit 0.

Commit:

```bash
git add lib/slo_rules_engine/provider.rb lib/slo_rules_engine/providers/datadog.rb lib/slo_rules_engine/providers/prometheus_stack.rb lib/slo_rules_engine/providers/sloth.rb bin/rules-ctl test/providers_test.rb test/cli_test.rb
git commit -m "feat: declare provider automation modes"
git push origin main
```

## Task 2: Generic Apply Plan Contract

**Files:**
- Create: `lib/slo_rules_engine/apply.rb`
- Modify: `lib/slo_rules_engine.rb`
- Modify: `bin/rules-ctl`
- Test: `test/apply_test.rb`
- Test: `test/cli_test.rb`

- [ ] **Step 1: Write failing apply primitive tests**

Create `test/apply_test.rb`:

```ruby
# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/slo_rules_engine'

class ApplyTest < Minitest::Test
  def test_apply_plan_serializes_operations
    operation = SloRulesEngine::ApplyOperation.new(
      action: 'create',
      target: 'datadog.slo',
      name: 'checkout-api successful requests',
      source: 'artifacts.slos[0]',
      payload: { name: 'checkout-api successful requests' }
    )
    plan = SloRulesEngine::ApplyPlan.new(provider: 'datadog', mode: 'dry_run', operations: [operation])

    payload = plan.to_h

    assert_equal 'datadog', payload.fetch(:provider)
    assert_equal 'dry_run', payload.fetch(:mode)
    assert_equal 'create', payload.fetch(:operations).fetch(0).fetch(:action)
    assert_equal 'datadog.slo', payload.fetch(:operations).fetch(0).fetch(:target)
    assert_equal 'artifacts.slos[0]', payload.fetch(:operations).fetch(0).fetch(:source)
  end

  def test_apply_plan_knows_when_it_is_empty
    plan = SloRulesEngine::ApplyPlan.new(provider: 'datadog', mode: 'dry_run', operations: [])

    assert plan.empty?
  end
end
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `ruby -Ilib test/apply_test.rb`

Expected: failure because `SloRulesEngine::ApplyOperation` is not defined.

- [ ] **Step 3: Implement apply primitives**

Create `lib/slo_rules_engine/apply.rb`:

```ruby
# frozen_string_literal: true

module SloRulesEngine
  class UnsupportedApplyAction < StandardError; end

  ApplyOperation = Struct.new(:action, :target, :name, :source, :payload, :backend_id, keyword_init: true) do
    def to_h
      {
        action: action,
        target: target,
        name: name,
        source: source,
        payload: payload,
        backend_id: backend_id
      }.compact
    end
  end

  ApplyPlan = Struct.new(:provider, :mode, :operations, keyword_init: true) do
    def initialize(**kwargs)
      super
      self.operations ||= []
    end

    def empty?
      operations.empty?
    end

    def to_h
      {
        provider: provider,
        mode: mode,
        empty: empty?,
        operations: operations.map(&:to_h)
      }
    end
  end
end
```

Require it from `lib/slo_rules_engine.rb`.

- [ ] **Step 4: Add CLI apply command shape**

In `bin/rules-ctl`, add usage and command dispatch for:

```text
bin/rules-ctl apply --provider=<provider> [--dry-run] [--confirm] [--output-dir=<dir>] <definitionfile...>
```

For this task, the command may fail with `UnsupportedApplyAction` after loading provider metadata. The full behavior arrives in later tasks.

- [ ] **Step 5: Run tests and commit**

Run:

```bash
ruby -Ilib test/apply_test.rb
ruby -Ilib test/cli_test.rb
```

Expected: both commands exit 0.

Commit:

```bash
git add lib/slo_rules_engine/apply.rb lib/slo_rules_engine.rb bin/rules-ctl test/apply_test.rb test/cli_test.rb
git commit -m "feat: add provider apply plan primitives"
git push origin main
```

## Task 3: Manifest Bundle Apply Support

**Files:**
- Create: `lib/slo_rules_engine/appliers/manifest_bundle.rb`
- Modify: `lib/slo_rules_engine.rb`
- Modify: `bin/rules-ctl`
- Test: `test/apply_test.rb`
- Test: `test/cli_test.rb`

- [ ] **Step 1: Write failing manifest bundle tests**

Add to `test/apply_test.rb`:

```ruby
def test_manifest_bundle_applier_plans_manifest_write
  manifest = { provider: 'prometheus_stack', service: 'checkout-api', artifacts: { recording_rules: [] } }
  applier = SloRulesEngine::Appliers::ManifestBundle.new(output_dir: '/tmp/generated')

  plan = applier.plan(manifest)

  assert_equal 'prometheus_stack', plan.provider
  assert_equal 'dry_run', plan.mode
  assert_equal 'write', plan.operations.fetch(0).action
  assert_equal 'manifest_file', plan.operations.fetch(0).target
  assert_equal '/tmp/generated/checkout-api/prometheus_stack/manifest.json', plan.operations.fetch(0).payload.fetch(:path)
end
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `ruby -Ilib test/apply_test.rb`

Expected: failure because `SloRulesEngine::Appliers::ManifestBundle` is not defined.

- [ ] **Step 3: Implement manifest bundle applier**

Create `lib/slo_rules_engine/appliers/manifest_bundle.rb`:

```ruby
# frozen_string_literal: true

require 'fileutils'

module SloRulesEngine
  module Appliers
    class ManifestBundle
      def initialize(output_dir:)
        @output_dir = output_dir
      end

      def plan(manifest)
        ApplyPlan.new(
          provider: manifest.fetch(:provider),
          mode: 'dry_run',
          operations: [
            ApplyOperation.new(
              action: 'write',
              target: 'manifest_file',
              name: "#{manifest.fetch(:service)} #{manifest.fetch(:provider)} manifest",
              source: 'manifest',
              payload: { path: manifest_path(manifest), manifest: manifest }
            )
          ]
        )
      end

      def apply(manifest)
        plan(manifest).tap do |apply_plan|
          apply_plan.operations.each do |operation|
            path = operation.payload.fetch(:path)
            FileUtils.mkdir_p(File.dirname(path))
            File.write(path, JSON.pretty_generate(operation.payload.fetch(:manifest)))
          end
        end
      end

      private

      def manifest_path(manifest)
        File.join(@output_dir, manifest.fetch(:service), manifest.fetch(:provider), 'manifest.json')
      end
    end
  end
end
```

- [ ] **Step 4: Wire `apply` for `manifest_bundle` and `external_generator`**

In `bin/rules-ctl`, route `prometheus_stack` and `sloth` through `ManifestBundle`.

Rules:

- dry-run prints the plan and does not write files.
- live apply requires `--confirm`.
- live apply writes manifest files only.

- [ ] **Step 5: Run tests and commit**

Run:

```bash
ruby -Ilib test/apply_test.rb
ruby -Ilib test/cli_test.rb
scripts/verify.sh
```

Expected: all commands exit 0.

Commit:

```bash
git add lib/slo_rules_engine/appliers/manifest_bundle.rb lib/slo_rules_engine.rb bin/rules-ctl test/apply_test.rb test/cli_test.rb
git commit -m "feat: apply manifest-backed provider outputs"
git push origin main
```

## Task 4: Datadog API Apply Plan And Client

**Files:**
- Create: `lib/slo_rules_engine/datadog/client.rb`
- Create: `lib/slo_rules_engine/appliers/datadog.rb`
- Modify: `lib/slo_rules_engine.rb`
- Modify: `bin/rules-ctl`
- Test: `test/datadog_apply_test.rb`
- Test: `test/cli_test.rb`

- [x] **Step 1: Write failing Datadog dry-run tests**

Create `test/datadog_apply_test.rb`:

```ruby
# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/slo_rules_engine'

class DatadogApplyTest < Minitest::Test
  def test_datadog_applier_plans_slos_monitors_gap_monitors_and_dashboards
    definition = load_checkout
    manifest = SloRulesEngine.default_provider_registry.fetch('datadog').generate(definition).to_h.merge(service: definition.service)
    applier = SloRulesEngine::Appliers::Datadog.new(client: FakeDatadogClient.new)

    plan = applier.plan(manifest)

    assert_equal 'datadog', plan.provider
    assert_equal 'dry_run', plan.mode
    assert_equal ['datadog.slo', 'datadog.monitor', 'datadog.monitor', 'datadog.dashboard'], plan.operations.map(&:target)
  end

  def test_datadog_live_apply_requires_credentials
    client = SloRulesEngine::Datadog::Client.new(api_key: nil, app_key: nil)

    assert_raises(SloRulesEngine::Datadog::MissingCredentials) do
      client.validate_credentials!
    end
  end

  private

  def load_checkout
    SloRulesEngine.clear_definitions
    load File.expand_path('../examples/services/checkout.rb', __dir__)
    SloRulesEngine.definitions.fetch(0)
  end

  class FakeDatadogClient
    def existing_state
      { slos: {}, monitors: {}, dashboards: {} }
    end
  end
end
```

- [x] **Step 2: Run the focused test and verify it fails**

Run: `ruby -Ilib test/datadog_apply_test.rb`

Expected: failure because Datadog applier and client are not defined.

- [x] **Step 3: Implement Datadog client**

Create `lib/slo_rules_engine/datadog/client.rb` with:

```ruby
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

module SloRulesEngine
  module Datadog
    class MissingCredentials < StandardError; end
    class ApiError < StandardError; end

    class Client
      TRANSIENT_CODES = %w[429 500 502 503 504].freeze

      def initialize(api_key: ENV['DD_API_KEY'], app_key: ENV['DD_APP_KEY'], site: ENV.fetch('DD_SITE', 'datadoghq.com'), http: Net::HTTP, sleep_fn: ->(seconds) { sleep(seconds) })
        @api_key = api_key
        @app_key = app_key
        @base_uri = URI("https://api.#{site}")
        @http = http
        @sleep_fn = sleep_fn
      end

      def validate_credentials!
        raise MissingCredentials, 'DD_API_KEY and DD_APP_KEY are required for live Datadog apply' if @api_key.to_s.empty? || @app_key.to_s.empty?
      end

      def existing_state
        { slos: {}, monitors: {}, dashboards: {} }
      end

      def request(method, path, payload: nil, retries: 3)
        validate_credentials!
        uri = @base_uri.dup
        uri.path = path
        attempt = 0
        begin
          attempt += 1
          response = perform(method, uri, payload)
          return JSON.parse(response.body.empty? ? '{}' : response.body) if %w[200 201 202].include?(response.code)
          raise ApiError, "Datadog #{method} #{path} failed with #{response.code}: #{response.body}" unless TRANSIENT_CODES.include?(response.code) && attempt <= retries
          @sleep_fn.call(retry_after(response))
          retry
        end
      end

      private

      def perform(method, uri, payload)
        klass = { 'POST' => Net::HTTP::Post, 'PUT' => Net::HTTP::Put, 'GET' => Net::HTTP::Get, 'DELETE' => Net::HTTP::Delete }.fetch(method)
        request = klass.new(uri.request_uri, headers)
        request.body = JSON.generate(payload) if payload
        @http.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') { |connection| connection.request(request) }
      end

      def headers
        {
          'Accept' => 'application/json',
          'Content-Type' => 'application/json',
          'DD-API-KEY' => @api_key,
          'DD-APPLICATION-KEY' => @app_key
        }
      end

      def retry_after(response)
        [response['X-RateLimit-Reset'].to_i, 1].max
      end
    end
  end
end
```

- [x] **Step 4: Implement Datadog applier**

Map current Datadog artifacts into operations:

- `artifacts.slos[*]` -> `datadog.slo`
- `artifacts.monitors[*]` -> `datadog.monitor`
- `artifacts.telemetry_gap_monitors[*]` -> `datadog.monitor`
- `artifacts.dashboards[*]` -> `datadog.dashboard`

Use imported state from `client.existing_state` to choose `create` or `update` by name.

- [x] **Step 5: Add live apply execution**

Live Datadog apply requires `--confirm`. Use endpoints:

- SLO create: `POST /api/v1/slo`
- SLO update: `PUT /api/v1/slo/<id>`
- monitor create: `POST /api/v1/monitor`
- monitor update: `PUT /api/v1/monitor/<id>`
- dashboard create: `POST /api/v1/dashboard`
- dashboard update: `PUT /api/v1/dashboard/<id>`

The first implementation may use synthetic payloads derived from generated artifacts; tests assert paths, methods, and payload provenance rather than contacting Datadog.

- [x] **Step 6: Run tests and commit**

Run:

```bash
ruby -Ilib test/datadog_apply_test.rb
ruby -Ilib test/cli_test.rb
scripts/verify.sh
```

Expected: all commands exit 0.

Commit:

```bash
git add lib/slo_rules_engine/datadog/client.rb lib/slo_rules_engine/appliers/datadog.rb lib/slo_rules_engine.rb bin/rules-ctl test/datadog_apply_test.rb test/cli_test.rb
git commit -m "feat: add datadog apply planning"
git push origin main
```

## Task 5: Backend Telemetry Lookup Adapters

**Files:**
- Create: `lib/slo_rules_engine/telemetry_lookup.rb`
- Create: `lib/slo_rules_engine/telemetry_lookup/datadog.rb`
- Create: `lib/slo_rules_engine/telemetry_lookup/prometheus.rb`
- Modify: `lib/slo_rules_engine.rb`
- Modify: `bin/rules-ctl`
- Test: `test/telemetry_lookup_test.rb`
- Test: `test/cli_test.rb`

- [x] **Step 1: Write failing telemetry lookup tests**

Create `test/telemetry_lookup_test.rb`:

```ruby
# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/slo_rules_engine'

class TelemetryLookupTest < Minitest::Test
  def test_lookup_result_serializes_normalized_signals
    signal = SloRulesEngine::TelemetryLookup::Signal.new(
      kind: 'latency',
      metric: 'http.server.request.duration',
      user_visible: true,
      source: 'datadog'
    )
    result = SloRulesEngine::TelemetryLookup::Result.new(provider: 'datadog', signals: [signal], findings: [])

    payload = result.to_h

    assert_equal 'datadog', payload.fetch(:provider)
    assert_equal 'latency', payload.fetch(:signals).fetch(0).fetch(:kind)
    assert_equal 'http.server.request.duration', payload.fetch(:signals).fetch(0).fetch(:metric)
  end
end
```

- [x] **Step 2: Run focused test and verify it fails**

Run: `ruby -Ilib test/telemetry_lookup_test.rb`

Expected: failure because telemetry lookup objects are not defined.

- [x] **Step 3: Implement lookup objects**

Create `Signal`, `Finding`, and `Result` structs under `SloRulesEngine::TelemetryLookup`, each with `to_h`.

- [x] **Step 4: Add provider lookup adapters**

Add Datadog and Prometheus-compatible adapters that accept injectable clients. They should produce normalized `Signal` objects and findings without requiring live network in tests.

- [x] **Step 5: Add CLI command**

Add:

```text
bin/rules-ctl lookup-telemetry --provider=<provider> --metric=<metric> [--kind=<kind>] [--user-visible=true|false]
```

The initial CLI may require explicit metric names. Backend discovery by service selector can be added in a later slice.

- [x] **Step 6: Run tests and commit**

Run:

```bash
ruby -Ilib test/telemetry_lookup_test.rb
ruby -Ilib test/cli_test.rb
scripts/verify.sh
```

Expected: all commands exit 0.

Commit:

```bash
git add lib/slo_rules_engine/telemetry_lookup.rb lib/slo_rules_engine/telemetry_lookup/datadog.rb lib/slo_rules_engine/telemetry_lookup/prometheus.rb lib/slo_rules_engine.rb bin/rules-ctl test/telemetry_lookup_test.rb test/cli_test.rb
git commit -m "feat: add backend telemetry lookup"
git push origin main
```

## Task 6: Online Provider Sanity Checks

**Files:**
- Modify: `lib/slo_rules_engine/reality_check.rb`
- Modify: `bin/rules-ctl`
- Test: `test/reality_check_test.rb`
- Test: `test/cli_test.rb`

- [x] **Step 1: Write failing online sanity-check tests**

Add tests that inject a fake provider lookup result and assert findings:

```ruby
def test_reality_check_reports_missing_backend_series
  checker = SloRulesEngine::RealityCheck::TelemetryBindingChecker.new(provider: 'datadog')
  definition = load_checkout
  report = checker.check(definition, [])

  assert report.findings.any? { |finding| finding.fetch(:code) == 'missing_provider_metric' }
end
```

- [x] **Step 2: Run focused test and verify it fails for the new online case**

Run: `ruby -Ilib test/reality_check_test.rb`

Expected: failure for any new methods not yet implemented.

- [x] **Step 3: Extend findings**

Support these codes:

- `missing_provider_binding`
- `missing_provider_metric`
- `missing_backend_series`
- `missing_histogram_bucket`
- `calculation_basis_low_volume`
- `calculation_basis_high_volume`

- [x] **Step 4: Add CLI output**

Keep `reality-check` machine-readable. Add optional online adapter execution only when requested by explicit flags so normal verification remains offline.

- [x] **Step 5: Run tests and commit**

Run:

```bash
ruby -Ilib test/reality_check_test.rb
ruby -Ilib test/cli_test.rb
scripts/verify.sh
```

Expected: all commands exit 0.

Commit:

```bash
git add lib/slo_rules_engine/reality_check.rb bin/rules-ctl test/reality_check_test.rb test/cli_test.rb
git commit -m "feat: add provider telemetry sanity findings"
git push origin main
```

## Task 7: Documentation And Provider Contribution Rules

**Files:**
- Modify: `README.md`
- Modify: `docs/features.md`
- Modify: `docs/evolution-plan.md`
- Modify: `docs/provider-contract.md`
- Modify: `docs/provider-contribution-guide.md`

- [ ] **Step 1: Document provider state modes**

Update provider docs with:

- `live_api`
- `manifest_bundle`
- `external_generator`
- required dry-run behavior
- explicit live mutation confirmation
- credential handling rule
- test fixture requirements

- [ ] **Step 2: Document telemetry lookup flow**

Update feature docs so telemetry-derived SLI/SLO generation uses:

- file inventory
- backend lookup output
- backend discovery output
- candidate review
- draft definition generation
- provider generation
- provider apply planning

- [ ] **Step 3: Run verification**

Run:

```bash
ruby -Ilib test/all_test.rb
scripts/verify.sh
ruby -Ilib test/forbidden_terms_test.rb
```

Expected: all commands exit 0.

- [ ] **Step 4: Commit and push**

Commit:

```bash
git add README.md docs/features.md docs/evolution-plan.md docs/provider-contract.md docs/provider-contribution-guide.md
git commit -m "docs: document provider state management"
git push origin main
```

## Self-Review

- Spec coverage: tasks cover provider automation metadata, apply planning, Datadog live API client, manifest-backed providers, telemetry lookup, sanity checks, and provider contribution docs.
- Placeholder scan: no deferred placeholders are required for the first implementation slice; out-of-scope behavior is explicitly listed in the design spec.
- Type consistency: `ApplyOperation`, `ApplyPlan`, provider `automation_mode`, provider `state_actions`, and `TelemetryLookup` objects are named consistently across tasks.
- Public-safety: all fixtures are synthetic and tests must keep `test/forbidden_terms_test.rb` green.

## Follow-Up Backlog From Implementation Review

- [ ] Add real Datadog provider-schema payload translation and backend state import so `live_api` means real create/update reconciliation instead of endpoint dispatch only.
- [ ] Add explicit reviewed-manifest input plus `diff`, `import`, and `prune` commands.
- [ ] Enforce provider capability metadata such as `apply_plan` against the documented provider contract.
- [ ] Expand calculation-basis findings across every SLI instance and SLO, not only the first.
- [ ] Record Sloth external-generator handoff details in apply plans instead of file write alone.
