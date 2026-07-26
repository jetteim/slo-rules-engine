# Implementation Plan

This is the running plan for the long refactor.

## Phase 1: Public Skeleton

- [x] Create public-safe repository scaffold.
- [x] Document feature inventory and provider contract.
- [x] Add minimal executable Ruby DSL.
- [x] Add neutral model objects.
- [x] Add validation result model.
- [x] Add provider registry.
- [x] Add `datadog` and `prometheus_stack` smoke providers.
- [x] Add `notification_router` as delivery integration, not provider.
- [x] Add sample service definitions.
- [x] Add tests and forbidden-term scan.
- [x] Add CLI entrypoint for telemetry-derived SLI/SLO candidates.
- [x] Add calculation-basis reality-check advisor.
- [x] Push public repository.
- [x] Add CI verification workflow.

## Phase 2: Onboarding And Reliability Modeling

- [x] Add provider-specific query bindings while preserving neutral metric intent.
- [x] Add provider capability validation before generation.
- [x] Add line references for validation messages.
- [x] Add calculation-basis recommendation rules.
- [x] Add alert route reference validation.
- [x] Add offline telemetry binding reality-check hooks.
- [x] Add backend API reality-check adapters.
- [x] Allow lookup-result envelopes to feed onboarding commands.
- [x] Add service-scoped telemetry discovery baseline.

## Phase 3: Provider Depth

- [x] Implement Datadog SLO, burn-rate monitor, telemetry-gap notification, and dashboard manifest generation.
- [x] Implement Prometheus-compatible recording, burn-rate, missing-telemetry, and alert rule manifest generation.
- [x] Implement Grafana dashboard manifest generation.
- [x] Implement notification-router route catalog generation.
- [x] Add notification-router route availability check manifests.
- [x] Add provider capability validation.
- [x] Add provider route-source validation.
- [x] Add generated provider manifest output directory.
- [x] Add provider artifact schemas for apply-ready outputs.
- [x] Add provider query binding reality-check report.
- [x] Add provider query/reality-check adapters.
- [ ] Add real Datadog provider-schema payload translation and backend state import for create/update reconciliation.
- [x] Add Datadog counter-ratio `time_slice` payload translation and diff reconciliation.
- [x] Add Datadog threshold-based `time_slice` payload translation for reviewed provider query expressions.
- [x] Add Datadog create-and-wait SLO apply and stale monitor recreate strategy.
- [x] Expand calculation-basis findings across every SLI instance and SLO.
- [x] Record Sloth external-generator handoff details in apply plans.
- [x] Write native Sloth spec files for external-generator apply, diff, and prune handoff.

## Phase 4: Provider State Management

- [x] Add backend change impact summary for diff, apply, and prune plans.
- [x] Add reviewed manifest input path for apply workflows.
- [x] Add explicit diff command.
- [x] Add explicit import command.
- [x] Add explicit prune command.
- [x] Add generated artifact diff harness.
- [x] Add provider-specific risk signaling to state plans.
- [x] Add identity-confidence signaling for weaker backend matches.
- [x] Block live Datadog update/recreate/prune mutations when ownership confidence is weak.
- [x] Require explicit engine-managed tags for Datadog fallback name/title ownership matches.
- [x] Detect ambiguous Datadog source-ref and fallback matches and degrade them to weak identity.

## Phase 5: Telemetry-First Adoption

- [x] Add batch telemetry discovery across service portfolios and selector inputs.
- [x] Add service onboarding summary that ranks discovered services and signals by review readiness.
- [x] Add candidate confidence and explanation output for telemetry-derived drafts.
- [x] Add saved evidence packets that preserve discovery findings, candidate reasoning, and review handoff state.
- [x] Add file-backed review acceptance for saved handoff packets.
- [x] Generate reviewed draft definitions from accepted handoff packets.
- [x] Validate accepted handoff packets before provider handoff.
- [x] Preserve reviewed handoff provenance through generated provider manifests.
- [x] Validate generated provider manifests retain review evidence before apply.
- [x] Expose reviewed handoff provenance in review summaries and model reports.
- [x] Add provenance-aware review checks to generated manifest review queues.
- [x] Add explicit review status rollups for provider artifact queues.
- [x] Add saved manifest-review queue reports alongside generated provider manifests.
- [x] Connect manifest-review findings back to handoff packet labels for reviewer navigation.
- [x] Add explicit saved output for manifest-review reports.
- [x] Detect stale manifest provenance against updated handoff packet review state.
- [x] Surface saved manifest-review report paths in generated artifact handoff output.
- [x] Add manifest-review report freshness metadata for generated artifact bundles.
- [x] Gate live apply on stale manifest-review evidence when handoff packets are supplied.
- [x] Gate live prune on stale manifest-review evidence when handoff packets are supplied.
- [x] Validate saved manifest-review report freshness against current manifests and handoff packets.
- [x] Surface manifest-review freshness validation commands and stale-finding codes in external-generator handoff plans.
- [x] Add compact onboarding artifact index tying discovery evidence, handoff packets, reviewed drafts, provider manifests, and manifest-review reports together.
- [x] Add next-action guidance to onboarding artifact indexes for incomplete saved handoff bundles.
- [x] Surface saved manifest-review report validity and blocking findings in onboarding artifact indexes.
- [x] Surface saved manifest-review report freshness and stale-report refresh guidance in onboarding artifact indexes.
- [x] Validate provider-level saved manifest-review report freshness against all saved provider manifests in multi-scope artifact indexes.
- [x] Make provider-level manifest-review validation and refresh commands reproducible across all current provider manifests.
- [x] Add a representative saved-artifact fixture and smoke-test the telemetry-first walkthrough through reviewed provider gates.

## Phase 6: Contract Hardening

- [x] Enforce provider capability metadata against the documented provider contract.
- [x] Separate reviewed manifest input from in-process regeneration during backend mutation workflows.

## Phase 7: Maintainability Housekeeping

- [x] Review test-suite dependency shape and recommend compaction opportunities without changing behavior.
- [x] Review abstraction layer placement and recommend compaction or relocation opportunities without changing behavior.
- [x] Pilot low-risk test support helpers for CLI and onboarding fixtures.
- [x] Extract shared Datadog fake client and response test fixtures.
- [x] Extract onboarding CLI command module after test support guardrails exist.
- [x] Split Datadog apply coverage by behavior while preserving assertions.
- [x] Extract Datadog risk policy from the Datadog applier.
- [x] Extract catalog CLI command module after command-family coverage exists.
- [x] Extract Datadog payload translator from the Datadog applier.
- [x] Extract telemetry CLI command module after command-family coverage exists.
- [x] Extract Datadog state planner from the Datadog applier.
- [x] Split Datadog backend state reader from client transport concerns.
- [x] Extract report CLI command module after command-family coverage exists.
- [x] Extract Datadog request transport and retry behavior from the Datadog client.
- [ ] Pause further housekeeping unless a future behavior change exposes a clean seam without reducing readability.
