# Implementation Plan

This is the running plan for the long refactor.

## Phase 1: Public Skeleton

- [x] Create public-safe repository scaffold.
- [x] Document feature inventory and provider contract.
- [x] Document migration map.
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

## Phase 2: DSL Compatibility

- [ ] Expand DSL methods to match existing service definition shape.
- [x] Add provider-specific query bindings while preserving neutral metric intent.
- [ ] Add line references for validation messages.
- [ ] Add calculation-basis rules.
- [ ] Add SLO reality-check hooks.

## Phase 3: Provider Depth

- [ ] Implement Datadog SLO and monitor artifact generation.
- [ ] Implement Prometheus-compatible recording and alert rule generation.
- [ ] Implement Grafana dashboard generation.
- [ ] Implement notification-router route catalog generation.
- [ ] Add provider capability validation.

## Phase 4: Migration Tooling

- [ ] Add old-DSL compatibility report.
- [ ] Add anonymization helper for examples.
- [ ] Add generated artifact diff harness.
- [ ] Add import guidance for existing service files.
