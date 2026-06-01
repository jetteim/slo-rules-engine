# Telemetry-First Adoption Map

This document replaces copy-forward planning with a value-oriented adoption path.

The engine should help teams start from telemetry they already have, produce reviewed SLO intent quickly, and move accepted definitions into managed backend state without manual glue work.

## Primary Outcome

Turn measured service telemetry into a review-ready onboarding queue, reviewed SLO definitions, and managed provider artifacts.

## Adoption Flows

### 1. Service Portfolio Discovery To Review Queue

**Trigger:** many services emit telemetry, but there is no reviewed SLO backlog.

**Outcome:** a prioritized queue of services with evidence packets and review readiness scores.

**Needed capability increments:**

- batch telemetry discovery across service and selector scopes with one saved normalized evidence file per scope plus aggregate `index.json`
- service grouping from discovered telemetry
- readiness scoring based on eligibility, coverage, and data quality
- onboarding summary output for maintainers and platform teams

### 2. Service Evidence To Draft Definition

**Trigger:** one service has enough telemetry evidence to propose an SLO definition.

**Outcome:** a public-safe Ruby DSL draft with candidate SLIs/SLOs, conservative findings, and review notes.

**Needed capability increments:**

- candidate confidence and explanation
- saved evidence packets with findings, reasoning, and review handoff context
- draft generation that reuses normalized lookup and discovery envelopes
- validation that the draft remains loadable and reviewable

### 3. Reviewed Definition To Managed Provider State

**Trigger:** a maintainer accepts the neutral reliability intent.

**Outcome:** reviewed manifests can be diffed, imported, applied, pruned, and verified through explicit provider-state workflows.

**Needed capability increments:**

- backend change impact summaries for diff, apply, and prune plans
- stricter provider payload reconciliation
- explicit destructive-change signaling before mutation

## What We Are Not Optimizing For

- copying internal service definitions into this repository
- preserving organization-specific naming or routing conventions
- treating prior implementations as the product roadmap

## Current Best Next Value

1. pilot low-risk test support extraction for CLI and onboarding fixtures, preserving existing behavior and subprocess coverage
2. use the extracted test support as a guardrail before CLI command extraction or Datadog applier/client abstraction work
3. revisit provider-state only when new backend evidence exposes a concrete safety gap or another live provider is ready to follow the Datadog baseline

## Housekeeping Backlog

Completed recommendation reviews:

1. Test suite dependency and compaction review: `docs/housekeeping/test-suite-compaction-review.md`
2. Abstraction layer placement and compaction review: `docs/housekeeping/abstraction-layer-review.md`

Recommended housekeeping sequence:

1. Extract a small `test/support/cli_helpers.rb` pilot for a few manifest-review or onboarding CLI tests.
2. Extract public-safe onboarding handoff and discovery fixtures into `test/support/onboarding_fixtures.rb`.
3. Extract Datadog fake client/response helpers before splitting `test/datadog_apply_test.rb`.
4. Only after those guardrails exist, consider CLI command extraction and Datadog applier/client internal splits.
