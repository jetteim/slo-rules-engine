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
- [x] Pause incremental housekeeping unless a future behavior change exposes a
  clean seam without reducing readability.
- [x] Move CLI orchestration into the library boundary, retain a thin
  executable, consolidate command-ownership coverage, and centralize duplicated
  public-safe manifest fixtures through the atomic coherence checkpoint.

## Phase 8: Prometheus Stack Provider Completion

- [x] Generate base recording rules for every Prometheus-bound SLI instance independently of the number of attached SLOs.
- [x] Generate derived evaluation-window SLO success-ratio, error-ratio, objective, allowed/remaining error-budget, and policy-window burn-rate recording rules for every reviewed SLO.
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
- [x] Add fail-closed multi-target file-backed `bundle apply` after Phase 10
  shared result contracts and Phase 12 exact-plan guarantees.
- [x] Add read-only file-backed `bundle verify` with preflighted journal,
  execution, runtime, and plan integrity; fresh managed-file convergence
  evidence; explicit pending Sloth external state; and an immutable
  content-addressed `verified` successor.

## Phase 10: Provider-Neutral State-Manager Hardening

- [x] Define versioned provider-neutral desired-state, observed-state, change, plan/import, result, and finding contracts.
- [x] Preserve Datadog and Prometheus Stack provider payload, identity, finding, and risk evidence through the shared planning/import contracts.
- [x] Include Sloth native external-generator input state and missing-input findings in the shared import contract.
- [x] Define a durable operation-journal schema with deterministic plan and operation identity.
- [x] Persist initial journals from verified single-manifest dry-run plans and assess partial-failure/resume eligibility.
- [x] Record atomic Prometheus Stack and Sloth apply/prune transitions, attempts, failures, skips, and managed path identifiers.
- [x] Emit file-backed `ProviderStateResult` values linked to live plan and journal identity.
- [x] Refresh engine-owned files after apply/prune and persist expected/actual state fingerprints, timestamps, and stable verification findings.
- [x] Distinguish verified Sloth engine-owned inputs from pending downstream generator and Prometheus state.

## Phase 11: Production-Grade Datadog Reconciliation

- [x] Route confirmed Datadog apply/prune outcomes through durable operation journals and `ProviderStateResult`.
- [ ] Validate remaining Datadog SLO, monitor, and dashboard resource semantics using safe real-backend evidence.
- [ ] Complete provider-schema payload translation for supported create and update operations.
- [ ] Complete import and adoption behavior for managed resources with explicit identity confidence.
- [ ] Reconcile update, recreate, and prune behavior against current backend state without accepting weak ownership evidence.
- [x] Capture resulting backend identifiers and provider verification evidence after every confirmed mutation.
- [x] Discover and verify managed dashboards through the paginated custom-dashboard catalog instead of assuming manual dashboard-list membership.
- [x] Add an isolated Datadog sandbox setup guide plus read-only and explicitly confirmed temporary-dashboard contract smoke tests.
- [ ] Add public-safe contract fixtures for every verified Datadog request and response shape.

## Phase 12: Apply-Exact-Plan Workflow

- [x] Persist immutable file-backed provider change plans with desired-state, observed-state, manifest, review, and handoff fingerprints.
- [x] Add explicit plan review and confirmation metadata without storing credentials.
- [x] Recheck managed-file state immediately before execution and reject stale plans.
- [x] Execute only the file-backed operations recorded in the approved plan.
- [x] Link approved plan identity and evidence fingerprints through the durable operation journal and provider result.
- [x] Serialize exact applies per managed service/provider scope and reject concurrent execution.
- [ ] Extend approval and immediate state recheck to Datadog after safe live backend evidence is available.
- [x] Add idempotent completed-plan replay against a terminal operation journal after a fresh convergence check.
- [x] Resume journal-eligible file writes after a full state recheck while preserving attempt history.
- [ ] Extend exact-plan resume to Datadog only after live idempotency and backend recheck semantics are verified.
- [x] Verify final file state against the approved plan and emit manual rollback guidance when convergence fails.
- [ ] Extend final-state verification and rollback guidance to Datadog exact execution.

## Phase 13: Live SLO And Error-Budget Status

- [x] Add an explicit neutral SLO evaluation window with a `30d` compatibility default.
- [x] Generate window-correct Prometheus attainment, remaining-budget, and burn-rate recording rules.
- [x] Define a provider-neutral live SLO status model for objective attainment, error-budget remaining, burn rate, and telemetry freshness.
- [x] Add the read-only Prometheus-compatible status reader without moving PromQL into the neutral model.
- [ ] Add the Datadog status reader after safe live backend evidence is available.
- [x] Add a `status` command for exactly one reviewed Prometheus Stack manifest.
- [x] Extend `status` to one release bundle and a portfolio scope.
- [x] Distinguish healthy, at-risk, exhausted, missing-telemetry, and unverifiable states with machine-readable findings.
- [x] Link status output to reviewed SLO identity, owner, dashboard, playbook, and current provider resource identifiers.
- [x] Persist optional status reports with source timestamps and freshness metadata for later bundle review.
- [x] Preserve complete per-target reports, explicit unsupported-provider
  coverage, deterministic aggregate rollups, and partial query-failure
  evidence without persisting runtime endpoints.
- [x] Validate release-bundle freshness, portfolio manifests, review evidence,
  target identity, and all runtime mappings before the first aggregate backend
  read.
- [x] Capture content-addressed reviewed Sloth downstream evidence linking
  current manifest/native-input fingerprints to complete unambiguous generated
  recording-rule and provider-status query identities without provider calls.
- [x] Recheck saved Sloth downstream evidence identity and every local source
  fingerprint with stable stale findings before later consumers trust it.
- [x] Add the Sloth live-status reader using only fresh reviewed downstream
  evidence and explicit Prometheus runtime configuration.
- [x] Package optional current Sloth evidence per release target, accept one
  evidence reference per portfolio target, and include evidence-backed Sloth
  targets in aggregate status only after complete zero-client preflight.
- [x] Add a version-gated read-only adapter for the official Sloth HTTP MCP
  server, initially as an exact-identity comparison report; do not promote it
  to a status transport until neutral output parity is proven.
- [x] Extend release-bundle downstream verification to packaged current Sloth
  evidence and explicit read-only Prometheus-compatible runtimes without
  executing Sloth or reloading provider state.

## Phase 14: Agent-Operable Dual CLI And MCP

Detailed intent, requirements, feature packets, parity inventory, architecture,
and article revalidation live in
[`docs/agent-interface-roadmap.md`](agent-interface-roadmap.md).

- [x] **AICLI-F1:** define the versioned single command registry, register all
  38 pre-Agent Human CLI commands with schema references, side effects, safety
  gates, provider I/O, and output metadata, route Human dispatch through the
  registry, and publish a separate Human-command to Agent-JSON catalog without
  changing command behavior.
- [ ] **AICLI-F2:** add offline catalog/describe plus a strict Agent CLI raw
  JSON/file/stdin invocation path and versioned result/error envelopes.
  Offline bounded `agent catalog`, exact `agent describe`, JSON-only
  introspection errors, and strict resolved request schemas for all 40 current
  registry commands are complete. Raw JSON/file/stdin invocation and result
  envelopes remain open.
- [ ] **AICLI-F3:** add shared field-specific input hardening, generated/fuzz
  coverage, and zero-I/O `validate_only` for every write-capable command.
- [ ] **AICLI-F4:** add schema-checked field masks, declared limits/cursors,
  NDJSON streaming, explicit truncation, and response sanitization/quarantine.
- [ ] **AICLI-F5:** ship a versioned `SKILL.md` and compact agent context whose
  invariants are checked against the registry.
- [ ] **AICLI-F6:** expose eligible commands through an allowlisted MCP stdio
  adapter generated from the registry with headless credential references and
  no shell construction.
- [ ] **AICLI-F7:** close Human CLI, Agent CLI, schema, skill, and MCP parity;
  preserve existing Human CLI syntax/output/exit contracts; and pass every
  security, context-budget, compatibility, and no-I/O gate.

Phase 14 must not create a provider-payload bypass. Neutral intent, reviewed
provenance, freshness, ownership, exact-plan, confirmation, journal, and final
verification requirements apply identically through every interface.

## Project Backlog: Atomic Coherence-Preserving Simplification

- [x] Execute one repository-wide review, refactor, simplification, and cleanup
  checkpoint as a single revertible delivery unit, without adding product
  features or weakening any requirement, intent, provider contract, output,
  safety gate, public-safe boundary, or supported use case. Completion requires
  a before/after traceability map from requirements and engineering use cases to
  executable tests; characterization coverage for every changed boundary;
  removal or consolidation of demonstrated duplication and accidental
  complexity; compatibility of documented CLI, schemas, provider artifacts,
  findings, and refusal behavior; updated architecture and usage documentation;
  recorded before/after structural evidence; and the full verification suite.
  The checkpoint is atomic: it is complete only when all preservation and
  verification gates pass, and the entire branch/PR can be reverted as one unit.
  Completion evidence and accepted deferrals are recorded in
  `docs/housekeeping/atomic-coherence-simplification.md`.
