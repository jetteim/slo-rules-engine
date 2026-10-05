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

- implemented single versioned 40-command registry, separate Human-to-Agent
  JSON parity catalog, and offline bounded catalog/schema introspection
- strict raw command-request JSON invocation and result/error envelopes
- implemented workspace-confined adversarial file-input validation for
  validation/reporting and local file-backed diff, plus confined
  generation/review outputs and zero-I/O `validate_only`
- implemented URL/host/resource-ID safety for Agent telemetry lookup and
  single/batch discovery, including bounded/sanitized output, confined batch
  files, and pre-client zero-I/O validation
- implemented bounded/sanitized Agent candidate review plus confined in-place
  handoff review with credential-text rejection, bounded result projection,
  and zero-I/O `validate_only`; followed by validation-only coverage for other
  writes
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

The [housekeeping queue](housekeeping/project-structure-refactoring-plan.md#ordered-housekeeping-queue)
owns near-term work and the maintainer reassessment before feature growth.
Use the [maintainer guide](maintainer-guide.md) to locate the implementation for
an adoption workflow. Product outcomes and flow measures remain in this map;
implementation history is in [the implementation plan](implementation-plan.md).

## Housekeeping Backlog

Use the [structure plan](housekeeping/project-structure-refactoring-plan.md) for
preservation/dependency gates and the
[current abstraction audit](housekeeping/abstraction-layer-review.md) for
consolidation and ownership findings. Previous checkpoint inventories are in the
[archived handoff](housekeeping/archive/agents-2026-10-05.md); they do not set
current priorities. The [test topology review](housekeeping/test-suite-compaction-review.md)
remains historical supporting context.
