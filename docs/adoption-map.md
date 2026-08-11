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
- immutable bundle-native plan generation with provider-level change and risk summaries
- target-level approved plan artifacts with explicit reviewer attestation
- immediate managed-state recheck and execution of only stored operations
- deterministic multi-target file-backed execution with immutable applied-bundle evidence

### 5. Reviewed Reliability Intent To Current Operating Status

**Trigger:** a team needs current objective, budget, burn, and telemetry
freshness evidence for one service, a reviewed release, or an explicit service
portfolio.

**Outcome:** versioned per-SLO reports and deterministic aggregate rollups that
retain each target's evidence and make unsupported coverage explicit.

**Needed capability increments:**

- window-correct Prometheus Stack SLO and error-budget recording rules
- one-manifest GET-only status reads with normalized five-state classification
- release-bundle source validation before live reads
- credential-free portfolio inputs and explicit per-target runtime endpoints
- aggregate target/state rollups with retained partial query-failure evidence
- content-addressed reviewed Sloth downstream identity evidence with local
  freshness checks and no backend access
- one-manifest Sloth live status using only fresh exact-manifest downstream
  evidence and an explicit Prometheus runtime
- release and portfolio Sloth aggregate status using one current exact evidence
  artifact and explicit Prometheus-compatible runtime per readable target
- an implemented, version-gated official Sloth MCP provider adapter for
  read-only exact-identity/status comparison before any transport-parity claim

### 6. Reviewed Workflow To Agent-Safe Automation

**Trigger:** an AI agent needs to use the same onboarding, release, provider
state, and status workflows as an engineer without relying on stale prompt
documentation or ambiguous shell construction.

**Outcome:** feature-parity Human CLI and Agent CLI sub-interfaces expose strict
runtime-discoverable contracts, bounded/sanitized output, and identical safety
gates; MCP later projects the same registry.

**Needed capability increments:**

- implemented single versioned command registry and separate 38-command
  Human-to-Agent JSON parity catalog
- strict raw command-request JSON plus offline catalog/schema introspection
- shared adversarial input validation and zero-I/O `validate_only`
- field masks, limits/cursors, NDJSON, explicit truncation, and response
  sanitization
- versioned agent skill/context plus headless credential rules
- MCP stdio generated from the registry after safety and schema contracts are
  stable
- mandatory Human/Agent equivalence, compatibility, and security testing

## What We Are Not Optimizing For

- copying internal service definitions into this repository
- preserving organization-specific naming or routing conventions
- treating prior implementations as the product roadmap

## Current Best Next Value

1. resume AICLI-F2 from the implemented 38-command registry/catalog foundation
2. keep Datadog live status, contract testing, exact apply/resume, and Datadog
   live bundle verification postponed until isolated credentials are available
3. revalidate the Sloth MCP comparison against a tagged binary only after an
   official release includes MCP; retain direct Prometheus evidence as the
   contract-complete path

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
14. Atomic coherence-preserving simplification: thin executable, library CLI
    boundary, consolidated architecture coverage, shared public-safe manifest
    fixture, current architecture map, and repository-wide traceability
    evidence in `docs/housekeeping/atomic-coherence-simplification.md`

Recommended remaining housekeeping sequence:

1. Treat the atomic housekeeping checkpoint as complete.
2. Make no further structural change unless a feature exposes a focused,
   behavior-tested responsibility.
3. Preserve the thin executable and library orchestration boundary.
