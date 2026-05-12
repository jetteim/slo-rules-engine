# Telemetry Batch Discovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `discover-telemetry --scope-file` so one provider run can discover many service or selector scopes, persist one normalized evidence file per scope, and write an aggregate `index.json` for later review-readiness ranking and onboarding.

**Architecture:** Keep single-scope discovery behavior intact and add a separate batch orchestration layer that loads and validates scope files, calls the existing provider adapter once per scope, persists normalized per-scope results, and emits one aggregate run summary. Keep providers unchanged except for the requirement that their discovery and lookup interfaces remain reusable by later onboarding stages without provider-specific parsing.

**Tech Stack:** Ruby, Minitest, standard library JSON/FileUtils/Time/OptionParser, existing `rules-ctl` CLI, existing telemetry lookup adapters.

---

## File Structure

- Create `lib/slo_rules_engine/telemetry_batch_discovery.rb`: scope loading, scope validation, label normalization, per-scope execution, per-scope file writing, aggregate index output.
- Modify `lib/slo_rules_engine.rb`: require the new batch discovery component.
- Modify `bin/rules-ctl`: add `--scope-file` and `--output-dir` handling to `discover-telemetry`, keep single-scope behavior intact, and route batch discovery through the new helper.
- Create `test/telemetry_batch_discovery_test.rb`: pure unit tests for scope parsing, duplicate label detection, per-scope result writing, and aggregate index output.
- Modify `test/rules_ctl_test.rb`: direct CLI method tests using stubbed adapters for batch discovery success and per-scope runtime failure behavior.
- Modify `test/cli_test.rb`: real command-line parsing tests for `--scope-file` conflicts and required options.
- Modify `docs/provider-contract.md`: document the telemetry discovery and lookup interface contract, normalized batch evidence requirements, and provider scope constraints.
- Modify `docs/provider-contribution-guide.md`: document required adapter methods, normalized result expectations, batch-discovery compatibility, and negative-path test requirements.
- Modify `docs/adoption-map.md`: promote batch discovery as the first telemetry-first adoption increment.
- Modify `docs/implementation-plan.md`: mark the batch discovery slice complete once implemented.
- Modify `AGENTS.md`: record the new telemetry-first checkpoint and next slice.

## Implementation Notes

- Scope files should be JSON arrays only in the first slice.
- `--scope-file` is mutually exclusive with `--service`, `--selector`, and `--host`.
- `--output-dir` is required when `--scope-file` is present.
- One provider per batch run only.
- Per-scope result files must preserve the normalized onboarding envelope: `provider`, `scope`, `signals`, `findings`.
- The aggregate `index.json` should include counts and file references, not duplicate all signal payloads inline.
- Static validation failures should abort before any discovery work runs.
- Per-scope runtime failures should be recorded in the aggregate output and cause overall command exit status `1`, while still writing the aggregate index and any successful scope files.

## Task 1: Batch Discovery Domain Helper

**Files:**
- Create: `lib/slo_rules_engine/telemetry_batch_discovery.rb`
- Modify: `lib/slo_rules_engine.rb`
- Test: `test/telemetry_batch_discovery_test.rb`

- [ ] **Step 1: Write the failing batch discovery tests**

Create `test/telemetry_batch_discovery_test.rb`:

```ruby
# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'tmpdir'
require 'tempfile'
require_relative '../lib/slo_rules_engine'

class TelemetryBatchDiscoveryTest < Minitest::Test
  def test_load_scopes_rejects_entries_without_scope_fields
    Tempfile.create(['scopes', '.json']) do |file|
      file.write(JSON.generate([{ label: 'empty-scope' }]))
      file.flush

      error = assert_raises(ArgumentError) do
        SloRulesEngine::TelemetryBatchDiscovery.load_scopes(file.path, provider: 'datadog')
      end

      assert_includes error.message, 'must define at least one of service, selectors, or host'
    end
  end

  def test_load_scopes_rejects_duplicate_normalized_labels
    Tempfile.create(['scopes', '.json']) do |file|
      file.write(JSON.generate([
        { label: 'checkout prod', service: 'checkout-api' },
        { label: 'checkout-prod', service: 'checkout-worker' }
      ]))
      file.flush

      error = assert_raises(ArgumentError) do
        SloRulesEngine::TelemetryBatchDiscovery.load_scopes(file.path, provider: 'prometheus_stack')
      end

      assert_includes error.message, 'duplicate normalized label'
    end
  end

  def test_runner_writes_one_result_per_scope_and_index
    adapter = FakeDiscoveryAdapter.new(
      {
        ['checkout-api', { 'env' => 'prod' }, nil] => SloRulesEngine::TelemetryLookup::Result.new(
          provider: 'datadog',
          signals: [SloRulesEngine::TelemetryLookup.discovered_signal(metric: 'http.server.request.duration', source: 'datadog')],
          findings: []
        ),
        [nil, { 'team' => 'payments' }, nil] => SloRulesEngine::TelemetryLookup::Result.new(
          provider: 'datadog',
          signals: [SloRulesEngine::TelemetryLookup.discovered_signal(metric: 'payments.checkout.completed', source: 'datadog')],
          findings: []
        )
      }
    )
    scopes = [
      SloRulesEngine::TelemetryBatchDiscovery::Scope.new(label: 'checkout-prod', service: 'checkout-api', selectors: { 'env' => 'prod' }),
      SloRulesEngine::TelemetryBatchDiscovery::Scope.new(label: 'payments-prod', selectors: { 'team' => 'payments' })
    ]

    Dir.mktmpdir do |dir|
      result = SloRulesEngine::TelemetryBatchDiscovery::Runner.new(
        provider: 'datadog',
        adapter: adapter,
        output_dir: dir,
        time_fn: -> { '2026-05-12T10:00:00Z' }
      ).run(scopes)

      assert_equal 2, result.fetch(:total_scopes)
      assert_equal 2, result.fetch(:successful_scopes)
      assert_equal 0, result.fetch(:failed_scopes)
      assert File.exist?(File.join(dir, 'checkout-prod.json'))
      assert File.exist?(File.join(dir, 'payments-prod.json'))
      assert File.exist?(File.join(dir, 'index.json'))

      checkout_payload = JSON.parse(File.read(File.join(dir, 'checkout-prod.json')))
      assert_equal 'datadog', checkout_payload.fetch('provider')
      assert_equal 'checkout-prod', checkout_payload.fetch('scope').fetch('label')
      assert_equal 1, checkout_payload.fetch('signals').length
    end
  end

  class FakeDiscoveryAdapter
    def initialize(results)
      @results = results
    end

    def discover(service: nil, selectors: {}, host: nil)
      @results.fetch([service, selectors, host])
    end
  end
end
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
ruby -Ilib test/telemetry_batch_discovery_test.rb
```

Expected: failure because `SloRulesEngine::TelemetryBatchDiscovery` is not defined.

- [ ] **Step 3: Implement the batch discovery helper**

Create `lib/slo_rules_engine/telemetry_batch_discovery.rb`:

```ruby
# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'time'

module SloRulesEngine
  module TelemetryBatchDiscovery
    Scope = Struct.new(:label, :service, :selectors, :host, keyword_init: true) do
      def to_h
        {
          label: label,
          service: service,
          selectors: selectors,
          host: host
        }.compact
      end
    end

    module_function

    def load_scopes(path, provider:)
      payload = JSON.parse(File.read(path), symbolize_names: true)
      raise ArgumentError, 'scope file must contain a JSON array' unless payload.is_a?(Array)

      scopes = payload.each_with_index.map do |entry, index|
        raise ArgumentError, "scope entry #{index} must be an object" unless entry.is_a?(Hash)

        selectors = (entry[:selectors] || {}).transform_keys(&:to_s).transform_values(&:to_s)
        scope = Scope.new(
          label: normalize_label(entry[:label] || default_label(entry, index)),
          service: entry[:service],
          selectors: selectors,
          host: entry[:host]
        )
        validate_scope!(scope, provider: provider, index: index)
        scope
      end

      labels = scopes.map(&:label)
      duplicate = labels.find { |label| labels.count(label) > 1 }
      raise ArgumentError, "duplicate normalized label #{duplicate.inspect}" if duplicate

      scopes
    end

    def normalize_label(value)
      value.to_s.strip.downcase.gsub(/[^a-z0-9._-]+/, '-').gsub(/-+/, '-').gsub(/\A-|-\z/, '')
    end

    def default_label(entry, index)
      return entry[:service] unless entry[:service].to_s.empty?
      return entry[:host] unless entry[:host].to_s.empty?

      "scope-#{index + 1}"
    end

    def validate_scope!(scope, provider:, index:)
      if scope.service.to_s.empty? && scope.selectors.empty? && scope.host.to_s.empty?
        raise ArgumentError, "scope entry #{index} must define at least one of service, selectors, or host"
      end
      raise ArgumentError, "scope entry #{index} has empty normalized label" if scope.label.to_s.empty?
      if provider == 'datadog' && !scope.host.to_s.empty? && (!scope.service.to_s.empty? || !scope.selectors.empty?)
        raise ArgumentError, 'Datadog scope entries cannot combine host with service or selectors'
      end
      if provider != 'datadog' && !scope.host.to_s.empty?
        raise ArgumentError, 'host scope is only supported for datadog discovery'
      end
    end

    class Runner
      def initialize(provider:, adapter:, output_dir:, time_fn: -> { Time.now.utc.iso8601 })
        @provider = provider
        @adapter = adapter
        @output_dir = output_dir
        @time_fn = time_fn
      end

      def run(scopes)
        FileUtils.mkdir_p(@output_dir)
        scope_results = scopes.map { |scope| run_scope(scope) }
        index_payload = {
          provider: @provider,
          generated_at: @time_fn.call,
          total_scopes: scope_results.length,
          successful_scopes: scope_results.count { |entry| entry.fetch(:status) == 'ok' },
          failed_scopes: scope_results.count { |entry| entry.fetch(:status) == 'error' },
          scopes: scope_results
        }
        File.write(File.join(@output_dir, 'index.json'), JSON.pretty_generate(index_payload))
        index_payload
      end

      private

      def run_scope(scope)
        result = @adapter.discover(service: scope.service, selectors: scope.selectors, host: scope.host)
        payload = result.to_h.merge(scope: scope.to_h)
        file_name = "#{scope.label}.json"
        File.write(File.join(@output_dir, file_name), JSON.pretty_generate(payload))
        {
          label: scope.label,
          scope: scope.to_h,
          status: 'ok',
          result_file: file_name,
          signal_count: payload.fetch(:signals).length,
          finding_count: payload.fetch(:findings).length
        }
      rescue StandardError => error
        {
          label: scope.label,
          scope: scope.to_h,
          status: 'error',
          signal_count: 0,
          finding_count: 0,
          error: {
            code: 'discovery_failed',
            message: error.message
          }
        }
      end
    end
  end
end
```

Require it in `lib/slo_rules_engine.rb`:

```ruby
require_relative 'slo_rules_engine/telemetry_batch_discovery'
```

- [ ] **Step 4: Run the focused test to verify it passes**

Run:

```bash
ruby -Ilib test/telemetry_batch_discovery_test.rb
```

Expected: `0 failures, 0 errors`.

- [ ] **Step 5: Commit**

```bash
git add lib/slo_rules_engine.rb lib/slo_rules_engine/telemetry_batch_discovery.rb test/telemetry_batch_discovery_test.rb
git commit -m "feat: add telemetry batch discovery runner"
git push origin main
```

## Task 2: CLI Scope File Wiring

**Files:**
- Modify: `bin/rules-ctl`
- Modify: `test/rules_ctl_test.rb`
- Modify: `test/cli_test.rb`

- [ ] **Step 1: Write the failing CLI tests**

Add to `test/cli_test.rb`:

```ruby
def test_discover_telemetry_scope_file_requires_output_dir
  Tempfile.create(['scopes', '.json']) do |file|
    file.write(JSON.generate([{ label: 'checkout-prod', service: 'checkout-api' }]))
    file.flush

    _stdout, stderr, status = Open3.capture3(
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'discover-telemetry',
      '--provider=prometheus_stack',
      "--scope-file=#{file.path}"
    )

    refute status.success?
    assert_includes stderr, 'missing --output-dir'
  end
end

def test_discover_telemetry_scope_file_rejects_single_scope_flags
  Tempfile.create(['scopes', '.json']) do |file|
    file.write(JSON.generate([{ label: 'checkout-prod', service: 'checkout-api' }]))
    file.flush

    _stdout, stderr, status = Open3.capture3(
      'ruby',
      "#{ROOT}/bin/rules-ctl",
      'discover-telemetry',
      '--provider=prometheus_stack',
      "--scope-file=#{file.path}",
      '--service=checkout-api',
      '--output-dir=/tmp/discovery'
    )

    refute status.success?
    assert_includes stderr, '--scope-file cannot be combined with --service, --selector, or --host'
  end
end
```

Add to `test/rules_ctl_test.rb`:

```ruby
def test_discover_telemetry_scope_file_writes_index_and_exits_zero_when_all_scopes_succeed
  fake_adapter = Object.new
  fake_adapter.define_singleton_method(:discover) do |service: nil, selectors: {}, host: nil|
    SloRulesEngine::TelemetryLookup::Result.new(
      provider: 'prometheus_stack',
      signals: [SloRulesEngine::TelemetryLookup.discovered_signal(metric: "metric.for.#{service || selectors.fetch('team')}", source: 'prometheus')],
      findings: []
    )
  end

  Tempfile.create(['scopes', '.json']) do |file|
    file.write(JSON.generate([
      { label: 'checkout-prod', service: 'checkout-api' },
      { label: 'payments-prod', selectors: { team: 'payments' } }
    ]))
    file.flush

    Dir.mktmpdir do |dir|
      stdout, _stderr = capture_io do
        SloRulesEngine::TelemetryLookup::Prometheus.stub(:new, fake_adapter) do
          RulesCtl.discover_telemetry([
            '--provider=prometheus_stack',
            "--scope-file=#{file.path}",
            "--output-dir=#{dir}"
          ])
        end
      end

      payload = JSON.parse(stdout)
      assert_equal 'prometheus_stack', payload.fetch('provider')
      assert_equal 2, payload.fetch('successful_scopes')
      assert_equal 0, payload.fetch('failed_scopes')
      assert File.exist?(File.join(dir, 'index.json'))
    end
  end
end
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run:

```bash
ruby -Ilib test/rules_ctl_test.rb
ruby -Ilib test/cli_test.rb
```

Expected: failures because `discover-telemetry` does not understand `--scope-file` or `--output-dir`.

- [ ] **Step 3: Implement CLI batch mode**

In `bin/rules-ctl`, extend `discover_telemetry`:

```ruby
scope_file = nil
output_dir = nil

parser = OptionParser.new do |opts|
  opts.on('--scope-file=FILE', 'JSON file containing discovery scopes') { |value| scope_file = value }
  opts.on('--output-dir=DIR', 'Directory for batch discovery output') { |value| output_dir = value }
end
```

Add conflict handling:

```ruby
if scope_file
  if !service.to_s.empty? || !selector_values.empty? || !host.to_s.empty?
    abort_usage('--scope-file cannot be combined with --service, --selector, or --host')
  end
  abort_usage('missing --output-dir') if output_dir.to_s.empty?
end
```

Route batch mode through the helper:

```ruby
if scope_file
  scopes = SloRulesEngine::TelemetryBatchDiscovery.load_scopes(scope_file, provider: provider_key)
  adapter = telemetry_lookup_adapter(provider_key, base_url: base_url, from: from, to: to)
  result = SloRulesEngine::TelemetryBatchDiscovery::Runner.new(
    provider: provider_key,
    adapter: adapter,
    output_dir: output_dir
  ).run(scopes)
  puts JSON.pretty_generate(result)
  exit(result[:failed_scopes].zero? ? 0 : 1)
end
```

Leave the current single-scope discovery path unchanged under the `scope_file.nil?` branch.

- [ ] **Step 4: Run the CLI tests to verify they pass**

Run:

```bash
ruby -Ilib test/rules_ctl_test.rb
ruby -Ilib test/cli_test.rb
```

Expected: `0 failures, 0 errors`.

- [ ] **Step 5: Commit**

```bash
git add bin/rules-ctl test/rules_ctl_test.rb test/cli_test.rb
git commit -m "feat: add scope-file telemetry discovery"
git push origin main
```

## Task 3: Per-Scope Runtime Failure Reporting

**Files:**
- Modify: `test/rules_ctl_test.rb`
- Modify: `lib/slo_rules_engine/telemetry_batch_discovery.rb`

- [ ] **Step 1: Write the failing mixed-success batch test**

Add to `test/rules_ctl_test.rb`:

```ruby
def test_discover_telemetry_scope_file_records_failed_scopes_and_exits_one
  fake_adapter = Object.new
  fake_adapter.define_singleton_method(:discover) do |service: nil, selectors: {}, host: nil|
    if service == 'checkout-api'
      SloRulesEngine::TelemetryLookup::Result.new(
        provider: 'datadog',
        signals: [SloRulesEngine::TelemetryLookup.discovered_signal(metric: 'http.server.request.duration', source: 'datadog')],
        findings: []
      )
    else
      raise 'backend query failed'
    end
  end

  Tempfile.create(['scopes', '.json']) do |file|
    file.write(JSON.generate([
      { label: 'checkout-prod', service: 'checkout-api' },
      { label: 'payments-prod', selectors: { team: 'payments' } }
    ]))
    file.flush

    Dir.mktmpdir do |dir|
      stdout, _stderr = capture_io do
        exit_error = assert_raises(SystemExit) do
          SloRulesEngine::TelemetryLookup::Datadog.stub(:new, fake_adapter) do
            RulesCtl.discover_telemetry([
              '--provider=datadog',
              "--scope-file=#{file.path}",
              "--output-dir=#{dir}"
            ])
          end
        end
        assert_equal 1, exit_error.status
      end

      payload = JSON.parse(stdout)
      assert_equal 1, payload.fetch('successful_scopes')
      assert_equal 1, payload.fetch('failed_scopes')
      failed_scope = payload.fetch('scopes').find { |entry| entry.fetch('status') == 'error' }
      assert_equal 'discovery_failed', failed_scope.fetch('error').fetch('code')
    end
  end
end
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
ruby -Ilib test/rules_ctl_test.rb
```

Expected: failure because batch discovery does not yet exit `1` for partial failure or preserve the error contract in the aggregate index.

- [ ] **Step 3: Implement per-scope error reporting**

In `lib/slo_rules_engine/telemetry_batch_discovery.rb`, keep the existing rescue branch and ensure the aggregate index counts failed scopes exactly:

```ruby
{
  label: scope.label,
  scope: scope.to_h,
  status: 'error',
  signal_count: 0,
  finding_count: 0,
  error: {
    code: 'discovery_failed',
    message: error.message
  }
}
```

In `bin/rules-ctl`, keep:

```ruby
exit(result[:failed_scopes].zero? ? 0 : 1)
```

- [ ] **Step 4: Run the focused tests to verify they pass**

Run:

```bash
ruby -Ilib test/rules_ctl_test.rb
ruby -Ilib test/telemetry_batch_discovery_test.rb
```

Expected: `0 failures, 0 errors`.

- [ ] **Step 5: Commit**

```bash
git add lib/slo_rules_engine/telemetry_batch_discovery.rb test/rules_ctl_test.rb test/telemetry_batch_discovery_test.rb
git commit -m "feat: report batch discovery scope failures"
git push origin main
```

## Task 4: Provider Docs, Backlog, And Handoff

**Files:**
- Modify: `docs/provider-contract.md`
- Modify: `docs/provider-contribution-guide.md`
- Modify: `docs/adoption-map.md`
- Modify: `docs/implementation-plan.md`
- Modify: `AGENTS.md`
- Test: `test/forbidden_terms_test.rb`

- [ ] **Step 1: Write the failing documentation expectation test**

Add to `test/cli_test.rb`:

```ruby
def test_discover_telemetry_scope_file_help_lists_batch_option
  stdout, stderr, status = Open3.capture3(
    'ruby',
    "#{ROOT}/bin/rules-ctl",
    'discover-telemetry',
    '--help'
  )

  assert status.success?, stderr
  assert_includes stdout, '--scope-file=FILE'
  assert_includes stdout, '--output-dir=DIR'
end
```

- [ ] **Step 2: Run the focused test and verify it fails or is incomplete**

Run:

```bash
ruby -Ilib test/cli_test.rb
```

Expected: failure until the CLI help text includes the new batch flags.

- [ ] **Step 3: Update docs and help text**

Update `bin/rules-ctl` option help strings to include:

```ruby
opts.on('--scope-file=FILE', 'JSON file containing discovery scopes') { |value| scope_file = value }
opts.on('--output-dir=DIR', 'Directory for batch discovery output') { |value| output_dir = value }
```

Update `docs/provider-contract.md` to add:

```markdown
- `discover-telemetry --scope-file` may orchestrate repeated `discover(...)` calls for one provider run.
- discovery-capable providers must document supported scope inputs, unsupported combinations, and batch compatibility.
- discovery and lookup output must remain reusable by later onboarding stages without provider-specific parsing.
```

Update `docs/provider-contribution-guide.md` to add:

```markdown
- discovery-capable providers must support the shared batch-discovery contract or state explicitly why they do not.
- tests must cover invalid scope combinations and normalized batch output reuse.
```

Update `docs/adoption-map.md` first flow to say batch discovery now produces saved per-scope evidence plus aggregate index output.

Update `docs/implementation-plan.md` to mark batch discovery complete after implementation.

Update `AGENTS.md` to record the checkpoint and move the next telemetry-first slice to review-readiness ranking.

- [ ] **Step 4: Run verification and confirm docs are clean**

Run:

```bash
ruby -Ilib test/cli_test.rb
ruby -Ilib test/all_test.rb
ruby -Ilib test/forbidden_terms_test.rb
./scripts/verify.sh
git status --short --branch
```

Expected:

- all test commands exit `0`
- `verification ok`
- worktree shows only the intended telemetry batch discovery changes before commit

- [ ] **Step 5: Commit**

```bash
git add bin/rules-ctl docs/provider-contract.md docs/provider-contribution-guide.md docs/adoption-map.md docs/implementation-plan.md AGENTS.md test/cli_test.rb
git commit -m "docs: define telemetry batch discovery contract"
git push origin main
```
