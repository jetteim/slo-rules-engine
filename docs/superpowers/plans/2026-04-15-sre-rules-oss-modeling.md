# SRE Rules OSS Reliability Modeling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build OSS-safe reliability modeling depth for the SLO rules engine, with the primary capability being SLI/SLO draft generation from existing telemetry inventory and without importing private rule definitions, private identifiers, or generated private artifacts.

**Architecture:** The engine remains a three-layer system: Ruby DSL, neutral reliability model, and provider/integration outputs. This plan strengthens the neutral reliability layer so SLI/SLO intent, miss-policy, measurement details, review gates, and observability handoff are explicit before any backend artifact generation.

**Tech Stack:** Ruby, Minitest, JSON fixtures, existing `bin/rules-ctl`, existing provider registry, existing forbidden-term test.

---

## Architecture Execution Brief

**Parent:** OSS-ready SRE rules exercise

**Decision:** Generate reviewable SLI/SLO drafts from measured telemetry first, then model reliability intent explicitly; provider-specific artifacts are later generated outputs.

**Outcome:** Maintainers can point the engine at existing telemetry inventory, receive a public-safe draft service definition with candidate SLIs and SLOs, review SLO quality, error-budget policy, miss-policy readiness, and observability gaps, then generate Datadog, Prometheus-compatible, dashboard, or routing artifacts.

**Scope:** Included: neutral model fields, DSL methods, validation, synthetic examples, model report CLI, provider contribution guide, docs, public-safety guardrails. Excluded: private rule files, private metrics/selectors, private routing targets, private service inventory, backend API apply flows.

**Architecture impact:** C4 container scope is `slo-rules-engine`; component changes are `DSL`, `Model`, `Validation`, `RealityCheck`, `CLI`, and `Docs`. Providers consume enriched model fields but do not own reliability decisions.

**Implementation handoff:** Six features below, followed by task-level TDD steps.

**Evidence:** `ruby -Ilib test/all_test.rb`, `scripts/verify.sh`, and forbidden-term scan.

**Open questions:** Confirm whether model-report output should be JSON-only first, or JSON plus Markdown. Default plan uses JSON-only for testability and avoids accidental prose leakage.

## Primary Capability: Generate SLIs And SLOs From Existing Telemetry

This is the most important capability. The intended onboarding path is not manual SLO authoring first; it is telemetry lookup first, then generated candidate review.

Explicit features to implement:

1. **Telemetry Inventory Ingestion:** Accept a measured telemetry inventory JSON file as the starting point.
2. **Signal Eligibility Review:** Reject unsupported, non-user-visible, or metric-less signals with machine-readable findings.
3. **SLI/SLO Candidate Inference:** Map eligible signals to default SLI identifiers, SLO identifiers, objectives, success conditions, and calculation-basis recommendations.
4. **Draft Definition Generation:** Emit a public-safe Ruby DSL draft containing service, owner, candidate SLIs, metric bindings, instances, and SLOs.
5. **Generated Draft Validation:** Ensure the emitted draft can be loaded and validated by the existing DSL and validator.
6. **Review Handoff:** Preserve findings and conservative review language so generated SLOs remain proposals, not automatic production policy.
7. **Provider Handoff:** Keep backend provider generation downstream of accepted draft definitions; providers must not invent SLO policy.

## Value Stream

1. Author public-safe service reliability definition.
2. Validate model completeness and public safety.
3. Review SLI/SLO quality, objective realism, calculation basis, miss-policy, and observability handoff.
4. Generate provider artifacts only after model review passes.
5. Use synthetic examples to document adoption patterns.

## Capability Map

- **Telemetry-Derived SLO Drafting:** measured telemetry inventory, eligibility findings, SLI/SLO inference, draft DSL generation, validation handoff.
- **Reliability Intent Capture:** service profile, users/consumers, SLIs, SLI instances, SLOs, measurement details, reality-check notes.
- **Miss-Policy Modeling:** trigger, response, authority, exit condition, review cadence.
- **Observability Handoff:** telemetry binding gaps, dashboard needs, alert context needs, backend generation requests.
- **Provider Contribution Safety:** provider boundaries, guardrails, fixture rules, deterministic output expectations, unsupported-field behavior, and review checklist.
- **OSS Safety:** fixture taxonomy, forbidden-term expansion, local-only private input boundary.
- **Model Review CLI:** machine-readable review report for SLO quality and readiness.

## Feature Packets

1. **Feature: Public Safety Boundary**
   Acceptance: target repo contains only synthetic fixtures and generic docs; tests fail on forbidden internal terms and private artifact filename patterns.

2. **Feature: Telemetry-To-Draft SLO Generation**
   Acceptance: `bin/rules-ctl draft-definition --service=checkout-api --owner=payments-platform examples/telemetry/checkout-signals.json` emits a loadable Ruby DSL draft with candidate SLIs/SLOs and excludes rejected telemetry.

3. **Feature: Reliability Model Enrichment**
   Acceptance: model supports measurement details, miss-policy, observability handoff, user-visible rationale, and reality-check notes without changing provider syntax.

4. **Feature: DSL Support**
   Acceptance: synthetic service definitions can express the enriched model concisely.

5. **Feature: Validation Gates**
   Acceptance: validation rejects missing required reliability fields for page-worthy SLOs and warns for review-only gaps.

6. **Feature: Model Review CLI**
   Acceptance: `bin/rules-ctl model-report examples/services/checkout.rb` emits JSON with accepted objects, warnings, and observability handoff requests.

7. **Feature: Documentation And Examples**
   Acceptance: docs explain modeling-first workflow with synthetic examples only.

8. **Feature: Provider Contribution Guide**
   Acceptance: docs include an extensive public contributor guide explaining what a provider is, what it is not, required guardrails, test expectations, and review criteria.

## File Structure

- Modify `lib/slo_rules_engine/model.rb`: add neutral reliability structs.
- Create `lib/slo_rules_engine/onboarding/definition_draft_generator.rb`: generate reviewable DSL drafts from telemetry candidates.
- Modify `lib/slo_rules_engine/dsl/service_definition.rb`: add DSL builders for model fields.
- Modify `lib/slo_rules_engine/validation.rb`: add reliability review validations.
- Create `lib/slo_rules_engine/reliability_model.rb`: model report builder and safe JSON serialization.
- Modify `lib/slo_rules_engine.rb`: require new reliability model file.
- Modify `bin/rules-ctl`: add `model-report` command.
- Modify `examples/services/checkout.rb`: add synthetic enriched reliability fields.
- Create `examples/services/background-worker.rb`: low-volume synthetic service for time-slice recommendation.
- Create `examples/telemetry/background-worker-signals.json`: synthetic telemetry fixture.
- Create `test/reliability_model_test.rb`: model report tests.
- Modify `test/all_test.rb`: include reliability model tests.
- Modify `test/onboarding_test.rb`: draft generator coverage.
- Modify `test/dsl_test.rb`: parser coverage for new DSL methods.
- Modify `test/validation_test.rb`: validation coverage for missing reliability fields.
- Modify `test/cli_test.rb`: CLI coverage for `model-report`.
- Modify `test/forbidden_terms_test.rb`: keep existing scan; add private artifact filename pattern check.
- Modify `docs/design.md`: document reliability model layer.
- Modify `docs/features.md`: document modeling-first features.
- Modify `docs/provider-contract.md`: document provider consumption of enriched fields.
- Create `docs/provider-contribution-guide.md`: contributor guide for provider implementations.
- Modify `README.md`: link model report and provider contribution guide.

## Task 0: Telemetry-To-Draft SLO Generation

**Files:**
- Create: `lib/slo_rules_engine/onboarding/definition_draft_generator.rb`
- Modify: `lib/slo_rules_engine.rb`
- Modify: `bin/rules-ctl`
- Modify: `test/onboarding_test.rb`
- Modify: `test/cli_test.rb`
- Modify: `docs/features.md`

- [ ] **Step 1: Write failing generator test**

Add coverage that a telemetry inventory with one eligible latency signal and one rejected saturation signal produces a Ruby DSL draft containing only the eligible candidate. Load the draft through the existing DSL and validate it.

- [ ] **Step 2: Write failing CLI test**

Add coverage for:

```bash
bin/rules-ctl draft-definition --service=checkout-api --owner=payments-platform examples/telemetry/checkout-signals.json
```

Expected: command exits 0, prints a Ruby DSL draft, includes `request-latency`, excludes non-user-visible saturation, and can be validated after saving.

- [ ] **Step 3: Implement draft generator**

Use `SloRulesEngine::Onboarding::CandidateGenerator` as the source of candidate truth. Do not duplicate eligibility logic. The draft generator should:

- accept `service`, `owner`, `environment`, and telemetry `signals`;
- emit `SRE.define`;
- emit one `sli` block per eligible candidate;
- bind the measured telemetry metric using `data_source 'telemetry-inventory'`;
- create a `default` instance;
- create one proposed `slo` block using inferred objective, success shape, calculation basis, and documentation;
- include comments for findings so rejected signals remain reviewable without becoming SLOs.

- [ ] **Step 4: Add CLI command**

Add:

```text
bin/rules-ctl draft-definition --service=<name> --owner=<owner> [--environment=<env>] <telemetry.json>
```

- [ ] **Step 5: Document feature list**

Update `docs/features.md` with the explicit telemetry-to-SLO feature list from this plan.

- [ ] **Step 6: Verify and commit**

Run:

```bash
ruby -Ilib test/onboarding_test.rb
ruby -Ilib test/cli_test.rb
ruby -Ilib test/all_test.rb
scripts/verify.sh
```

Expected: PASS.

## Task 1: Public Safety Boundary

**Files:**
- Modify: `test/forbidden_terms_test.rb`
- Test: `test/forbidden_terms_test.rb`

- [ ] **Step 1: Write failing test for private artifact filename patterns**

Add this test:

```ruby
def test_repository_does_not_contain_private_analysis_artifacts
  files = Dir.glob(File.join(ROOT, '**', '*'), File::FNM_DOTMATCH).select { |path| File.file?(path) }
  files.reject! { |path| path.include?('/.git/') }
  forbidden_patterns = [
    /\.private\./i,
    /raw-inventory/i,
    /source-snapshot/i,
    /nonpublic/i
  ]

  findings = files.filter_map do |path|
    relative = path.sub("#{ROOT}/", '')
    forbidden_patterns.find { |pattern| relative.match?(pattern) } && relative
  end

  assert_empty findings
end
```

- [ ] **Step 2: Run test to verify current safety**

Run: `ruby -Ilib test/forbidden_terms_test.rb`

Expected: PASS. If it fails, remove or rename only OSS-target files that violate the boundary; do not edit private source repos.

- [ ] **Step 3: Commit**

```bash
git add test/forbidden_terms_test.rb
git commit -m "test: guard against private modeling artifacts"
```

## Task 2: Reliability Model Enrichment

**Files:**
- Modify: `lib/slo_rules_engine/model.rb`
- Modify: `lib/slo_rules_engine.rb`
- Create: `test/reliability_model_test.rb`
- Modify: `test/all_test.rb`

- [ ] **Step 1: Write failing tests for new neutral objects**

Create `test/reliability_model_test.rb`:

```ruby
# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/sre'

class ReliabilityModelTest < Minitest::Test
  def test_measurement_details_are_serializable
    details = SloRulesEngine::MeasurementDetails.new(
      source: 'synthetic-metrics',
      measurement_point: 'server-side request boundary',
      caveats: ['synthetic fixture']
    )

    assert_equal(
      {
        source: 'synthetic-metrics',
        measurement_point: 'server-side request boundary',
        probe_interval: nil,
        probe_timeout: nil,
        threshold_requirements: [],
        excluded_traffic: [],
        caveats: ['synthetic fixture']
      },
      details.to_h
    )
  end

  def test_miss_policy_has_required_review_shape
    policy = SloRulesEngine::MissPolicy.new(
      trigger: 'error budget exhausted',
      response: 'assign one responder to restore service health',
      authority: 'pause risky changes for the affected service',
      exit_condition: 'SLO burn rate returns below policy threshold',
      review_cadence: 'next business day'
    )

    assert_equal 'error budget exhausted', policy.to_h.fetch(:trigger)
    assert_equal 'next business day', policy.to_h.fetch(:review_cadence)
  end
end
```

Modify `test/all_test.rb`:

```ruby
require_relative 'reliability_model_test'
```

- [ ] **Step 2: Run tests to verify failure**

Run: `ruby -Ilib test/reliability_model_test.rb`

Expected: FAIL with missing constants.

- [ ] **Step 3: Add minimal model structs**

Append to `lib/slo_rules_engine/model.rb`:

```ruby
MeasurementDetails = Struct.new(
  :source,
  :measurement_point,
  :probe_interval,
  :probe_timeout,
  :threshold_requirements,
  :excluded_traffic,
  :caveats,
  keyword_init: true
) do
  def initialize(**kwargs)
    super
    self.threshold_requirements ||= []
    self.excluded_traffic ||= []
    self.caveats ||= []
  end

  def to_h
    {
      source: source,
      measurement_point: measurement_point,
      probe_interval: probe_interval,
      probe_timeout: probe_timeout,
      threshold_requirements: threshold_requirements,
      excluded_traffic: excluded_traffic,
      caveats: caveats
    }
  end
end

MissPolicy = Struct.new(
  :trigger,
  :response,
  :authority,
  :exit_condition,
  :review_cadence,
  keyword_init: true
) do
  def to_h
    {
      trigger: trigger,
      response: response,
      authority: authority,
      exit_condition: exit_condition,
      review_cadence: review_cadence
    }
  end
end
```

- [ ] **Step 4: Run tests**

Run: `ruby -Ilib test/reliability_model_test.rb`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/slo_rules_engine/model.rb test/reliability_model_test.rb test/all_test.rb
git commit -m "feat: add neutral reliability model objects"
```

## Task 3: DSL Support For Reliability Intent

**Files:**
- Modify: `lib/slo_rules_engine/model.rb`
- Modify: `lib/slo_rules_engine/dsl/service_definition.rb`
- Modify: `examples/services/checkout.rb`
- Modify: `test/dsl_test.rb`

- [ ] **Step 1: Write failing DSL test**

Add to `test/dsl_test.rb`:

```ruby
def test_parses_reliability_intent_fields
  load File.expand_path('../examples/services/checkout.rb', __dir__)

  definition = SloRulesEngine.definitions.fetch(0)
  slo = definition.slis.fetch(0).instances.fetch(0).slos.fetch(0)

  assert_equal 'server-side request boundary', definition.slis.fetch(0).measurement_details.measurement_point
  assert_equal 'error budget exhausted', slo.miss_policy.trigger
  assert_equal ['bind provider queries', 'generate decision dashboard'], slo.observability_handoff.requests
end
```

- [ ] **Step 2: Run test to verify failure**

Run: `ruby -Ilib test/dsl_test.rb`

Expected: FAIL because fields and DSL methods do not exist.

- [ ] **Step 3: Add model fields**

Extend `SLI` in `lib/slo_rules_engine/model.rb` with `:user_visible_rationale` and `:measurement_details`.

Extend `SLO` with `:miss_policy`, `:reality_check_notes`, and `:observability_handoff`.

Add this struct:

```ruby
ObservabilityHandoff = Struct.new(:requests, keyword_init: true) do
  def initialize(**kwargs)
    super
    self.requests ||= []
  end

  def to_h
    { requests: requests }
  end
end
```

- [ ] **Step 4: Add DSL methods**

In `SLIBuilder`, add:

```ruby
def user_visible_rationale(value = nil)
  return @user_visible_rationale if value.nil?

  record_line(:user_visible_rationale)
  @user_visible_rationale = value.to_s
end

def measurement_details(&block)
  record_line(:measurement_details)
  @measurement_details = MeasurementDetailsBuilder.evaluate(&block)
end
```

In `SLOBuilder`, add:

```ruby
def miss_policy(&block)
  record_line(:miss_policy)
  @miss_policy = MissPolicyBuilder.evaluate(&block)
end

def reality_check_notes(*values)
  record_line(:reality_check_notes)
  @reality_check_notes = values.flatten.map(&:to_s)
end

def observability_handoff(*requests)
  record_line(:observability_handoff)
  @observability_handoff = ObservabilityHandoff.new(requests: requests.flatten.map(&:to_s))
end
```

Create builder classes in `lib/slo_rules_engine/dsl/service_definition.rb`:

```ruby
class MeasurementDetailsBuilder
  def self.evaluate(&block)
    new.tap { |builder| builder.instance_eval(&block) }.to_model
  end

  def source(value = nil)
    return @source if value.nil?

    @source = value.to_s
  end

  def measurement_point(value = nil)
    return @measurement_point if value.nil?

    @measurement_point = value.to_s
  end

  def probe_interval(value = nil)
    return @probe_interval if value.nil?

    @probe_interval = value.to_s
  end

  def probe_timeout(value = nil)
    return @probe_timeout if value.nil?

    @probe_timeout = value.to_s
  end

  def threshold_requirements(*values)
    @threshold_requirements = values.flatten.map(&:to_s)
  end

  def excluded_traffic(*values)
    @excluded_traffic = values.flatten.map(&:to_s)
  end

  def caveats(*values)
    @caveats = values.flatten.map(&:to_s)
  end

  def to_model
    MeasurementDetails.new(
      source: @source,
      measurement_point: @measurement_point,
      probe_interval: @probe_interval,
      probe_timeout: @probe_timeout,
      threshold_requirements: @threshold_requirements,
      excluded_traffic: @excluded_traffic,
      caveats: @caveats
    )
  end
end

class MissPolicyBuilder
  def self.evaluate(&block)
    new.tap { |builder| builder.instance_eval(&block) }.to_model
  end

  def trigger(value = nil)
    return @trigger if value.nil?

    @trigger = value.to_s
  end

  def response(value = nil)
    return @response if value.nil?

    @response = value.to_s
  end

  def authority(value = nil)
    return @authority if value.nil?

    @authority = value.to_s
  end

  def exit_condition(value = nil)
    return @exit_condition if value.nil?

    @exit_condition = value.to_s
  end

  def review_cadence(value = nil)
    return @review_cadence if value.nil?

    @review_cadence = value.to_s
  end

  def to_model
    MissPolicy.new(
      trigger: @trigger,
      response: @response,
      authority: @authority,
      exit_condition: @exit_condition,
      review_cadence: @review_cadence
    )
  end
end
```

- [ ] **Step 5: Update synthetic example**

Add to the sample SLI:

```ruby
user_visible_rationale 'Represents whether customers can complete checkout requests.'
measurement_details do
  source 'synthetic-otel-fixture'
  measurement_point 'server-side request boundary'
  threshold_requirements 'duration histogram with route and status dimensions'
  caveats 'synthetic example data only'
end
```

Add to the sample SLO:

```ruby
miss_policy do
  trigger 'error budget exhausted'
  response 'assign one responder to restore service health'
  authority 'pause risky changes for the affected service'
  exit_condition 'burn rate returns below policy threshold'
  review_cadence 'next business day'
end
reality_check_notes 'synthetic example objective; replace with historical review before production use'
observability_handoff 'bind provider queries', 'generate decision dashboard'
```

- [ ] **Step 6: Run tests and commit**

Run: `ruby -Ilib test/dsl_test.rb`

Expected: PASS.

```bash
git add lib/slo_rules_engine/model.rb lib/slo_rules_engine/dsl/service_definition.rb examples/services/checkout.rb test/dsl_test.rb
git commit -m "feat: capture reliability intent in DSL"
```

## Task 4: Validation Gates For Modeling

**Files:**
- Modify: `lib/slo_rules_engine/validation.rb`
- Modify: `test/validation_test.rb`

- [ ] **Step 1: Write failing validation tests**

Add to `test/validation_test.rb`:

```ruby
def test_warns_when_sli_lacks_user_visible_rationale
  definition = SloRulesEngine.definitions.fetch(0)
  definition.slis.fetch(0).user_visible_rationale = nil

  result = SloRulesEngine::CoreValidator.new.validate(definition)

  assert result.warnings.any? { |warning| warning.path.end_with?('.user_visible_rationale') }
end

def test_errors_when_slo_lacks_miss_policy
  definition = SloRulesEngine.definitions.fetch(0)
  definition.slis.fetch(0).instances.fetch(0).slos.fetch(0).miss_policy = nil

  result = SloRulesEngine::CoreValidator.new.validate(definition)

  refute result.valid?
  assert result.errors.any? { |error| error.path.end_with?('.miss_policy') }
end
```

- [ ] **Step 2: Run tests to verify failure**

Run: `ruby -Ilib test/validation_test.rb`

Expected: FAIL because validation does not inspect these fields.

- [ ] **Step 3: Add validation**

In `validate_slis`, after title validation:

```ruby
if empty?(sli.user_visible_rationale)
  result.warning("#{path}.user_visible_rationale", 'user-visible rationale should explain why this SLI represents service quality')
end
if sli.measurement_details.nil? || empty?(sli.measurement_details.measurement_point)
  result.warning("#{path}.measurement_details", 'measurement details should include measurement point')
end
```

In `validate_slos`, after success validation:

```ruby
if slo.miss_policy.nil?
  result.error("#{slo_path}.miss_policy", 'miss-policy is required for SLO review')
elsif empty?(slo.miss_policy.trigger) || empty?(slo.miss_policy.response) || empty?(slo.miss_policy.authority) || empty?(slo.miss_policy.exit_condition)
  result.error("#{slo_path}.miss_policy", 'miss-policy requires trigger, response, authority, and exit condition')
end
if slo.observability_handoff.nil? || slo.observability_handoff.requests.empty?
  result.warning("#{slo_path}.observability_handoff", 'observability handoff should list backend binding, alert, or dashboard work')
end
```

- [ ] **Step 4: Run tests and commit**

Run: `ruby -Ilib test/validation_test.rb`

Expected: PASS.

```bash
git add lib/slo_rules_engine/validation.rb test/validation_test.rb
git commit -m "feat: validate reliability modeling gates"
```

## Task 5: Model Review CLI

**Files:**
- Create: `lib/slo_rules_engine/reliability_model.rb`
- Modify: `lib/slo_rules_engine.rb`
- Modify: `bin/rules-ctl`
- Create: `test/reliability_model_test.rb` additions
- Modify: `test/cli_test.rb`

- [ ] **Step 1: Write failing model report test**

Add to `test/reliability_model_test.rb`:

```ruby
def test_model_report_summarizes_reliability_readiness
  SloRulesEngine.clear_definitions
  load File.expand_path('../examples/services/checkout.rb', __dir__)
  definition = SloRulesEngine.definitions.fetch(0)

  report = SloRulesEngine::ReliabilityModel::ReportBuilder.new.build([definition])

  assert_equal 1, report.fetch(:service_count)
  assert_equal 1, report.fetch(:slo_count)
  assert_empty report.fetch(:private_identifiers)
  assert_includes report.fetch(:observability_handoff_requests), 'bind provider queries'
end
```

- [ ] **Step 2: Run test to verify failure**

Run: `ruby -Ilib test/reliability_model_test.rb`

Expected: FAIL because report builder does not exist.

- [ ] **Step 3: Implement report builder**

Create `lib/slo_rules_engine/reliability_model.rb`:

```ruby
# frozen_string_literal: true

module SloRulesEngine
  module ReliabilityModel
    class ReportBuilder
      def build(definitions)
        slis = definitions.flat_map(&:slis)
        instances = slis.flat_map(&:instances)
        slos = instances.flat_map(&:slos)

        {
          service_count: definitions.size,
          sli_count: slis.size,
          instance_count: instances.size,
          slo_count: slos.size,
          calculation_basis_distribution: slos.map(&:calculation_basis).tally,
          objectives: slos.map(&:objective).compact.sort,
          observability_handoff_requests: slos.flat_map { |slo| slo.observability_handoff&.requests || [] }.uniq.sort,
          private_identifiers: []
        }
      end
    end
  end
end
```

Modify `lib/slo_rules_engine.rb`:

```ruby
require_relative 'slo_rules_engine/reliability_model'
```

- [ ] **Step 4: Add CLI command test**

Add to `test/cli_test.rb`:

```ruby
def test_model_report_command_outputs_json
  output = `bin/rules-ctl model-report examples/services/checkout.rb`
  assert $?.success?, output
  payload = JSON.parse(output)
  assert_equal 1, payload.fetch('service_count')
  assert_equal 1, payload.fetch('slo_count')
end
```

- [ ] **Step 5: Add CLI command**

In `bin/rules-ctl`, add command routing:

```ruby
when 'model-report'
  model_report(argv)
```

Add method:

```ruby
def model_report(argv)
  definitions = load_definitions(argv)
  puts JSON.pretty_generate(SloRulesEngine::ReliabilityModel::ReportBuilder.new.build(definitions))
end
```

Add usage line:

```text
bin/rules-ctl model-report <definitionfile...>
```

- [ ] **Step 6: Run tests and commit**

Run: `ruby -Ilib test/reliability_model_test.rb && ruby -Ilib test/cli_test.rb`

Expected: PASS.

```bash
git add lib/slo_rules_engine/reliability_model.rb lib/slo_rules_engine.rb bin/rules-ctl test/reliability_model_test.rb test/cli_test.rb
git commit -m "feat: add reliability model report"
```

## Task 6: Synthetic Low-Volume Example

**Files:**
- Create: `examples/services/background-worker.rb`
- Create: `examples/telemetry/background-worker-signals.json`
- Modify: `test/reality_check_test.rb`

- [ ] **Step 1: Add failing low-volume calculation-basis test**

Add to `test/reality_check_test.rb`:

```ruby
def test_low_volume_fixture_recommends_time_slice
  recommendation = SloRulesEngine::RealityCheck::CalculationBasisAdvisor.new.recommend(
    observations_per_second: 0.1,
    failed_observations_to_alert: 1
  )

  assert_equal 'time_slice', recommendation.basis
end
```

- [ ] **Step 2: Run test**

Run: `ruby -Ilib test/reality_check_test.rb`

Expected: PASS if advisor behavior already exists. If it fails, restore the reliability model rule: fewer than two failed observations that can trigger an alert should recommend `time_slice`.

- [ ] **Step 3: Add synthetic low-volume service fixture**

Create `examples/services/background-worker.rb` with a single synthetic SLI and SLO using `calculation_basis 'time_slice'`. Use generic names only: `background-worker`, `platform-team`, `job-completion`, `scheduled-run`, and `completed-runs`.

- [ ] **Step 4: Add telemetry fixture**

Create `examples/telemetry/background-worker-signals.json`:

```json
[
  {
    "kind": "availability",
    "metric": "worker.job.completed",
    "user_visible": true,
    "objective": 0.99,
    "success_condition": "Scheduled job completes successfully.",
    "observations_per_second": 0.1,
    "failed_observations_to_alert": 1
  }
]
```

- [ ] **Step 5: Validate fixtures and commit**

Run:

```bash
bin/rules-ctl validate examples/services/background-worker.rb
bin/rules-ctl candidates examples/telemetry/background-worker-signals.json
```

Expected: both commands exit 0.

```bash
git add examples/services/background-worker.rb examples/telemetry/background-worker-signals.json test/reality_check_test.rb
git commit -m "docs: add synthetic low-volume reliability example"
```

## Task 7: Provider Contribution Guide

**Files:**
- Create: `docs/provider-contribution-guide.md`
- Modify: `docs/provider-contract.md`
- Modify: `README.md`

- [ ] **Step 1: Write the provider boundary guide**

Create `docs/provider-contribution-guide.md` with these sections:

```markdown
# Provider Contribution Guide

## What A Provider Is

A provider is a deterministic adapter from the neutral reliability model to backend-specific artifacts. It translates validated service definitions into manifests, queries, monitors, dashboards, route mappings, or export files for one observability or incident-management backend.

A provider may:

- map neutral metric bindings to backend query syntax;
- render miss-policy, measurement caveats, notification routes, and dashboard variables;
- declare unsupported fields explicitly;
- emit warnings when backend capabilities cannot represent the neutral model;
- add backend-specific metadata needed to make generated artifacts useful and reviewable.

## What A Provider Is Not

A provider is not the source of reliability policy. It must not choose objectives, redefine calculation basis, invent service ownership, decide page policy, import private service definitions, store credentials, or apply changes to live systems as part of normal generation.

Provider generation must not require network access. Live apply flows, if ever added, require a separate explicit command, dry-run output, confirmation flow, and dedicated tests.

## Guardrails

- Consume the neutral model; do not bypass DSL validation.
- Keep output deterministic for identical inputs.
- Use synthetic fixtures only.
- Do not include secrets, internal hostnames, private service names, private routing targets, or private metric selectors.
- Treat unsupported backend features as explicit warnings, not silent drops.
- Preserve reliability intent fields even when the backend only accepts them as annotations.
- Keep backend-specific dependencies isolated to the provider layer.
- Add tests for generated output shape and unsafe-term scanning.
- Document every new provider option and its default behavior.

## Contribution Checklist

- Provider contract updated.
- Synthetic fixture added or reused.
- Unit tests cover supported output.
- Unsupported fields produce warnings.
- `ruby -Ilib test/all_test.rb` passes.
- `scripts/verify.sh` passes.
```

- [ ] **Step 2: Cross-link provider contract**

In `docs/provider-contract.md`, link the contribution guide and add a short warning that providers are translation adapters, not policy owners.

- [ ] **Step 3: Link from README**

Add a provider contribution link in the README development or documentation section.

- [ ] **Step 4: Verify and commit**

Run:

```bash
ruby -Ilib test/forbidden_terms_test.rb
```

Expected: PASS.

```bash
git add README.md docs/provider-contract.md docs/provider-contribution-guide.md
git commit -m "docs: add provider contribution guide"
```

## Task 8: Documentation Update

**Files:**
- Modify: `README.md`
- Modify: `docs/design.md`
- Modify: `docs/features.md`
- Modify: `docs/provider-contract.md`
- Modify: `docs/provider-contribution-guide.md`

- [ ] **Step 1: Update README CLI list**

Add:

```bash
bin/rules-ctl model-report examples/services/checkout.rb
```

- [ ] **Step 2: Update design docs**

In `docs/design.md`, add a section:

```markdown
## Reliability Modeling

The reliability model records SLI/SLO intent before backend generation. It includes measurement details, user-visible rationale, miss-policy, reality-check notes, and observability handoff requests. Providers may consume these fields, but they do not decide whether an SLO is appropriate.
```

- [ ] **Step 3: Update feature docs**

In `docs/features.md`, add a concise feature entry for modeling-first review:

```markdown
## Reliability Model Report

`rules-ctl model-report` summarizes the neutral reliability model for service definitions. It is intended for review before provider generation and uses synthetic examples in this repository.
```

- [ ] **Step 4: Update provider contract**

In `docs/provider-contract.md`, add:

```markdown
Providers receive reliability intent as input. They may render miss-policy, measurement caveats, playbook links, and dashboard variables into backend-specific artifacts, but objective selection and calculation-basis policy remain model decisions.
```

- [ ] **Step 5: Update provider contribution guide**

Ensure `docs/provider-contribution-guide.md` refers to the model-report command as the review point before provider generation.

- [ ] **Step 6: Run verification and commit**

Run:

```bash
ruby -Ilib test/all_test.rb
scripts/verify.sh
```

Expected: PASS.

```bash
git add README.md docs/design.md docs/features.md docs/provider-contract.md docs/provider-contribution-guide.md
git commit -m "docs: describe modeling-first reliability workflow"
```

## Traceability Review

- Value stream step 1 maps to Tasks 2, 3, and 6.
- Value stream step 2 maps to Tasks 1 and 4.
- Value stream step 3 maps to Tasks 4 and 5.
- Value stream step 4 maps to provider consumption documented in Tasks 7 and 8.
- Value stream step 5 maps to Task 6 and forbidden-term guard in Task 1.

No task requires private source files. Private analysis may inform generalized requirements outside this repository, but implementation must use synthetic examples and public-safe language only.

## Final Verification

Run:

```bash
ruby -Ilib test/all_test.rb
scripts/verify.sh
git status --short --branch
```

Expected:

- Test suite passes.
- Verification script exits 0.
- Working tree only contains intended commits.

Plan complete and saved to `docs/superpowers/plans/2026-04-15-sre-rules-oss-modeling.md`. Two execution options:

1. **Subagent-Driven (recommended)** - Dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints.
