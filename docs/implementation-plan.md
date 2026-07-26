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
- [x] Make provider-level report creation use all current manifests and shell-safe saved artifact paths.
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

## Phase 8: Prometheus Stack Provider Completion

- [x] Generate base recording rules for every Prometheus-bound SLI instance independently of the number of attached SLOs.
- [x] Generate derived SLO success-ratio, error-ratio, objective, error-budget, and burn-rate recording rules for every reviewed SLO.
- [x] Emit deterministic native PrometheusRule resources for recording, burn-rate, missing-telemetry, and alert rules.
- [x] Emit deterministic Grafana dashboard and Alertmanager routing bundle files while preserving reviewed manifest provenance.
- [x] Include every native Prometheus Stack bundle file in `plan`, `apply`, `diff`, `import`, and `prune`.
- [x] Validate native Prometheus Stack resource shape before confirmed file mutation.
- [x] Add a public-safe end-to-end Prometheus Stack bundle walkthrough and verification fixture.

## Phase 9: First-Class Onboarding And Release Bundle

- [x] Define a versioned bundle schema with stable bundle identity and lifecycle states.
- [x] Package discovery evidence, handoff decisions, reviewed definitions, provider manifests, review reports, and change plans into one bundle.
- [x] Record reviewer identity, review timestamp, decisions, notes, fingerprints, and provider targets without embedding credentials.
- [x] Add fail-closed `bundle create` and source-aware `bundle status` commands.
- [x] Add read-only `bundle plan` with explicit runtime configuration for every packaged provider target.
- [x] Make the `review_ready` to `apply_ready` transition deterministic and reject stale, invalid, incomplete, or already-planned predecessors.
- [x] Support multi-scope and multi-provider bundles with provider-level change and risk summaries.
- [ ] Add `bundle apply` only after Phase 10 defines shared execution and result contracts and Phase 12 defines exact-plan guarantees.
- [ ] Add `bundle verify` after provider-specific verification evidence has a shared Phase 10 contract.

## Phase 10: Provider-Neutral State-Manager Hardening

- [x] Define versioned provider-neutral desired-state, observed-state, change, plan/import, result, and finding contracts.
- [x] Preserve Datadog and Prometheus Stack provider payload, identity, finding, and risk evidence through the shared planning/import contracts.
- [x] Include Sloth native external-generator input state and missing-input findings in the shared import contract.
- [x] Define a durable operation-journal schema with deterministic plan and operation identity.
- [x] Persist initial journals from verified single-manifest dry-run plans and assess partial-failure/resume eligibility.
- [ ] Wire live execution outcomes into operation journals and add safe resumable execution.
- [ ] Add provider-specific post-apply verification evidence and managed resource identifiers.
- [ ] Define compensating rollback plans for reversible mutations and explicit findings for irreversible operations.

## Phase 11: Production-Grade Datadog Reconciliation

- [ ] Validate remaining Datadog SLO, monitor, and dashboard resource semantics using safe real-backend evidence.
- [ ] Complete provider-schema payload translation for supported create and update operations.
- [ ] Complete import and adoption behavior for managed resources with explicit identity confidence.
- [ ] Reconcile update, recreate, and prune behavior against current backend state without accepting weak ownership evidence.
- [ ] Capture resulting backend identifiers and provider verification evidence after every confirmed mutation.
- [ ] Add public-safe contract fixtures for every verified Datadog request and response shape.

## Phase 12: Apply-Exact-Plan Workflow

- [ ] Persist immutable provider change plans with desired-state, observed-state, manifest, review, and handoff fingerprints.
- [ ] Add explicit plan review and confirmation metadata without storing credentials.
- [ ] Recheck backend or managed-file state immediately before execution and reject stale plans.
- [ ] Execute only the operations recorded in the approved plan.
- [ ] Add idempotency and concurrency protection for conflicting applies against the same managed scope.
- [ ] Resume safely from operation journals after partial failure.
- [ ] Verify final provider state against the approved plan and emit rollback guidance when convergence fails.

## Phase 13: Live SLO And Error-Budget Status

- [ ] Define a provider-neutral live SLO status model for objective attainment, error-budget remaining, burn rate, and telemetry freshness.
- [ ] Add Datadog and Prometheus-compatible status readers without moving provider query syntax into the neutral model.
- [ ] Add a `status` command for one manifest, one bundle, or a portfolio scope.
- [ ] Distinguish healthy, at-risk, exhausted, missing-telemetry, and unverifiable states with machine-readable findings.
- [ ] Link status output to reviewed SLO identity, owner, dashboard, playbook, and current provider resource identifiers.
- [ ] Persist optional status reports with source timestamps and freshness metadata for later bundle review.
