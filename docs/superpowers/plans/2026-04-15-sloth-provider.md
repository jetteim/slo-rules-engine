# Sloth Provider Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a deterministic `sloth` provider that emits Sloth `prometheus/v1` SLO specs from the neutral reliability model.

**Architecture:** The Sloth provider stays inside the provider layer. It consumes reviewed model intent and Prometheus-compatible metric bindings, then emits Sloth spec artifacts; it does not run Sloth, contact a backend, or decide reliability policy.

**Tech Stack:** Ruby, Minitest, existing provider registry, existing CLI generation path, Sloth `prometheus/v1` spec shape.

---

## Task 1: Architecture Decision And Candidate Cleanup

Status: completed on branch `sre-rules-sloth-provider`.

**Files:**
- Create: `docs/superpowers/specs/2026-04-15-sloth-provider-design.md`
- Create: `docs/superpowers/plans/2026-04-15-sloth-provider.md`
- Modify: `README.md`
- Modify: `docs/provider-contract.md`

- [x] **Step 1: Record architecture decision**

Create the Sloth provider architecture brief with the candidate review, C4 component view, scope, risks, and verification path.

- [x] **Step 2: Update provider candidate docs**

Move `sloth` from future candidates to initial providers. Move `openslo` out of future provider candidates and into future interchange/export candidates.

- [x] **Step 3: Verify and commit**

Run:

```bash
ruby -Ilib test/forbidden_terms_test.rb
```

Expected: PASS.

Commit:

```bash
git add README.md docs/provider-contract.md docs/superpowers/specs/2026-04-15-sloth-provider-design.md docs/superpowers/plans/2026-04-15-sloth-provider.md
git commit -m "docs: select sloth as next provider"
```

## Task 2: Sloth Provider Generation

**Files:**
- Create: `lib/slo_rules_engine/providers/sloth.rb`
- Modify: `lib/slo_rules_engine.rb`
- Modify: `examples/services/checkout.rb`
- Modify: `test/providers_test.rb`
- Modify: `test/provider_bindings_test.rb`

- [ ] **Step 1: Write failing provider tests**

Add tests that:

- default provider registry lists `sloth`;
- `sloth` generates one `sloth_specs` artifact for `examples/services/checkout.rb`;
- the generated spec has `version: prometheus/v1`, service `checkout-api`, objective `99.9`, and Sloth event queries;
- the checkout metric has a `sloth` provider binding.

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
ruby -Ilib test/providers_test.rb
ruby -Ilib test/provider_bindings_test.rb
```

Expected: FAIL because `sloth` is not registered and checkout has no Sloth binding.

- [ ] **Step 3: Implement Sloth provider**

Create `Providers::Sloth < Provider`. Use capabilities:

```ruby
%w[
  sli_query_binding
  slo_evaluation
  burn_rate_alerting
  missing_telemetry_detection
  contextual_alerts
  notification_router_integration
  parameterized_dashboards
  reality_check
]
```

Emit:

```ruby
manifest(sloth_specs: [sloth_spec(definition)])
```

The Sloth spec must include:

- `version: 'prometheus/v1'`
- `service: definition.service`
- `labels: { owner: definition.owner }`
- one entry per SLO with `name`, `objective`, `description`, `sli.events.error_query`, `sli.events.total_query`, and `alerting` context.

- [ ] **Step 4: Register provider and update checkout binding**

Require `slo_rules_engine/providers/sloth` and register `Providers::Sloth.new`. Add a `provider_binding 'sloth'` block to the checkout metric using Prometheus-compatible data source, metric, range, and selector.

- [ ] **Step 5: Run focused tests**

Run:

```bash
ruby -Ilib test/providers_test.rb
ruby -Ilib test/provider_bindings_test.rb
```

Expected: PASS.

- [ ] **Step 6: Run full verification and commit**

Run:

```bash
ruby -Ilib test/all_test.rb
scripts/verify.sh
git diff --check
```

Expected: PASS.

Commit:

```bash
git add lib/slo_rules_engine/providers/sloth.rb lib/slo_rules_engine.rb examples/services/checkout.rb test/providers_test.rb test/provider_bindings_test.rb
git commit -m "feat: add sloth provider"
```

## Task 3: Sloth CLI And Documentation

**Files:**
- Modify: `README.md`
- Modify: `docs/provider-contract.md`
- Modify: `docs/features.md`
- Modify: `docs/superpowers/plans/2026-04-15-sloth-provider.md`
- Modify: `test/cli_test.rb`

- [ ] **Step 1: Write failing CLI test**

Add a CLI test for:

```bash
ruby bin/rules-ctl generate --provider=sloth examples/services/checkout.rb
```

Assert that the command exits 0, provider is `sloth`, and the first Sloth spec has `version` equal to `prometheus/v1`.

- [ ] **Step 2: Run test to verify failure or coverage gap**

Run:

```bash
ruby -Ilib test/cli_test.rb
```

Expected: PASS if registry support is already enough, or FAIL if JSON output shape needs adjustment.

- [ ] **Step 3: Update docs**

Update README CLI examples, provider contract, and feature docs to mention Sloth provider generation and OpenSLO as a future export/interchange target.

- [ ] **Step 4: Run verification and commit**

Run:

```bash
ruby -Ilib test/all_test.rb
scripts/verify.sh
ruby -Ilib test/forbidden_terms_test.rb
```

Expected: PASS.

Commit:

```bash
git add README.md docs/provider-contract.md docs/features.md docs/superpowers/plans/2026-04-15-sloth-provider.md test/cli_test.rb
git commit -m "docs: document sloth provider workflow"
```
