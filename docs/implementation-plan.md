# Implementation Plan

This is the running plan for the long refactor.

## Phase 1: Public Skeleton

- [x] Create public-safe repository scaffold.
- [x] Document feature inventory and provider contract.
- [x] Document migration map.
- [ ] Add minimal executable Ruby DSL.
- [ ] Add neutral model objects.
- [ ] Add validation result model.
- [ ] Add provider registry.
- [ ] Add `datadog`, `prometheus_stack`, and `notification_router` smoke providers.
- [ ] Add sample service definitions.
- [ ] Add tests and forbidden-term scan.
- [ ] Push public repository.

## Phase 2: DSL Compatibility

- [ ] Expand DSL methods to match existing service definition shape.
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
