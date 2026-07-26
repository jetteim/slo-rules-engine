# Telemetry-First Adoption Map

This document replaces copy-forward planning with a value-oriented adoption path.

The engine should help teams start from telemetry they already have, produce reviewed SLO intent quickly, and move accepted definitions into managed backend state without manual glue work.

## Primary Outcome

Turn measured service telemetry into a review-ready onboarding queue, reviewed SLO definitions, a content-addressed release bundle, and managed provider artifacts.

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

### 4. Reviewed Saved Artifacts To Release Boundary

**Trigger:** discovery, handoff, reviewed definitions, provider manifests, review reports, and optional change plans exist as separate files.

**Outcome:** one versioned, content-addressed release bundle records review attestation, packaged evidence, provider targets, lifecycle state, and source freshness.

**Needed capability increments:**

- deterministic bundle identity and artifact fingerprints
- fail-closed bundle creation for stale, incomplete, or credential-bearing inputs
- source-aware bundle status without backend calls
- provider-level plan and risk summaries before bundle apply behavior

## What We Are Not Optimizing For

- copying internal service definitions into this repository
- preserving organization-specific naming or routing conventions
- treating prior implementations as the product roadmap

## Current Best Next Value

1. add bundle-native plan generation and provider-level change/risk summaries
2. keep bundle apply deferred until its interaction with provider-neutral state contracts is explicit
3. harden provider-neutral state management after the first-class bundle planning boundary is proven
4. proceed to production-grade Datadog reconciliation, exact-plan execution, and live status in the accepted order
5. keep housekeeping paused unless feature work exposes a clean, behavior-tested boundary

## Housekeeping Backlog

Completed recommendation reviews:

1. Test suite dependency and compaction review: `docs/housekeeping/test-suite-compaction-review.md`
2. Abstraction layer placement and compaction review: `docs/housekeeping/abstraction-layer-review.md`

Recommended housekeeping sequence:

Completed guardrails:

1. CLI helper pilot: `test/support/cli_helpers.rb`
2. Public-safe onboarding handoff and discovery fixtures: `test/support/onboarding_fixtures.rb`
3. Datadog fake client/response helpers: `test/support/datadog_fakes.rb`
4. Datadog apply coverage split by behavior: `test/datadog_applier_state_test.rb`, `test/datadog_payload_translation_test.rb`, `test/datadog_client_state_test.rb`, and `test/datadog_client_http_test.rb`
5. First guarded CLI command extraction: `lib/slo_rules_engine/cli/onboarding_commands.rb`
6. Catalog CLI command extraction: `lib/slo_rules_engine/cli/catalog_commands.rb`
7. Datadog risk policy extraction: `lib/slo_rules_engine/datadog/risk_policy.rb`
8. Datadog payload translation extraction: `lib/slo_rules_engine/datadog/payload_translator.rb`
9. Telemetry CLI command extraction: `lib/slo_rules_engine/cli/telemetry_commands.rb`
10. Datadog state planning extraction: `lib/slo_rules_engine/datadog/state_planner.rb`
11. Datadog state reader split: `lib/slo_rules_engine/datadog/state_reader.rb`
12. Report CLI command extraction: `lib/slo_rules_engine/cli/report_commands.rb`
13. Datadog request transport extraction: `lib/slo_rules_engine/datadog/request_transport.rb`

Recommended remaining housekeeping sequence:

1. Pause further housekeeping unless a future change exposes a clean, behavior-tested seam.
2. Extract another focused CLI command module only if another command family changes.
3. Revisit test-suite compaction after the current collaborator and command-module count settles.
