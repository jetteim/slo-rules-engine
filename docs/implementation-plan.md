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
- [ ] Validate accepted handoff packets before provider handoff.

## Phase 6: Contract Hardening

- [x] Enforce provider capability metadata against the documented provider contract.
- [x] Separate reviewed manifest input from in-process regeneration during backend mutation workflows.
