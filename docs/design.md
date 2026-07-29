# Design

## Architecture

The engine is a local Ruby application with explicit boundaries around neutral
reliability intent, provider translation, reviewed evidence, state execution,
and read-only status.

```text
Operator / CI
  |
  v
bin/rules-ctl (thin executable)
  |
  v
RulesCtl library orchestration + command-family modules
  |
  +--> DSL / neutral model / validation
  +--> telemetry lookup and onboarding
  +--> provider generation and integrations
  +--> manifest review and release bundles
  +--> provider-state planning and execution
  +--> live SLO status readers
```

`bin/rules-ctl` only loads `lib/slo_rules_engine/cli.rb` and dispatches `ARGV`.
The library composes focused command-family modules for catalogs, onboarding,
telemetry, reports, release bundles, journals, approved plans, and live status.
Shared manifest/state orchestration remains in the library facade because those
commands intentionally share definition loading, provider validation, review
freshness, error rendering, and usage behavior.

## Component Boundaries

### Neutral Intent

`model.rb`, `dsl/`, `reliability_model.rb`, `validation.rb`, and
`burn_rate_policy.rb` own service, SLI, SLO, evaluation-window, calculation,
miss-policy, and response intent. They do not own PromQL, Datadog queries,
Sloth syntax, backend IDs, or credentials.

### Telemetry And Onboarding

`telemetry_lookup*`, `telemetry_batch_discovery.rb`, `reality_check.rb`, and
`onboarding/` turn backend evidence into normalized signals, review candidates,
handoff packets, reviewed drafts, and a saved artifact index. Telemetry is
evidence for human review, not authority to choose objectives or policy.

### Provider Translation

`provider.rb`, `providers/`, `prometheus_stack/`, `datadog/`, and
`integrations/` translate reviewed neutral intent into deterministic
provider-owned manifests and route intent. Providers report unsupported intent
instead of silently dropping it.

### Review And Release

`manifest_schema.rb`, `manifest_review_*`, and `release_bundle/` validate
provider artifacts, bind them to reviewed onboarding evidence, and package
content-addressed release lifecycles. Release bundles carry artifacts and
fingerprints, never runtime credentials.

### Provider State And Execution

`provider_state*`, `appliers/`, and provider-specific state collaborators own
desired/observed snapshots, plans, ownership/risk evidence, durable journals,
exact-plan approval, scope locking, execution, resume, and final verification.
Planning is observational. Confirmed mutation is fail-closed and journaled.

### Live Status

`live_status.rb` and `live_status/aggregate.rb` read generated Prometheus record
identities and normalize objective, budget, burn, freshness, and coverage.
Provider query syntax remains evidence in the reader. Live status never mutates
provider state and never persists runtime endpoints.

## Primary Flows

### Telemetry To Reviewed Intent

```text
backend telemetry
  -> normalized discovery evidence
  -> candidate reasoning
  -> reviewed handoff
  -> neutral Ruby definition
```

### Reviewed Intent To Provider State

```text
neutral Ruby definition
  -> core and provider validation
  -> provider manifest
  -> manifest review report
  -> content-addressed release bundle
  -> provider-state plan
  -> approved exact plan or confirmed provider action
  -> durable journal and verified provider result
  -> applied release bundle
  -> read-only managed-file verification
  -> verified release bundle
```

### Reviewed Intent To Current Status

```text
reviewed Prometheus Stack manifest
  -> generated recording-rule identities
  -> GET-only instant queries
  -> normalized per-SLO report
  -> optional release/portfolio aggregate
```

## Dependency Rules

- The neutral model must not depend on provider syntax or state.
- Providers may depend on neutral intent but must not mutate it.
- Release and approved-plan identities are content-addressed from reviewed
  evidence; runtime credentials and aggregate endpoints remain external.
- Provider payloads remain provider-shaped inside shared state contracts.
- CLI modules orchestrate domain collaborators; they do not implement provider
  policy.
- Delivery integrations route alert context but do not evaluate SLOs.
- File and backend mutations require explicit confirmation and durable
  execution evidence.

## Reliability And Safety

- Generation and bundle construction are deterministic and read-only.
- Invalid schemas, stale sources, missing review evidence, weak ownership, stale
  approved plans, scope conflicts, and incomplete runtime mappings fail before
  mutation or live reads.
- Confirmed execution stops after the first failed operation and preserves
  partial evidence.
- Completed exact plans replay only after a fresh convergence check; resume
  requires explicit state recheck.
- Backend failures are sanitized; credentials and raw private responses are not
  persisted.
- Public-safe terminology and fixtures are enforced by the verification suite.

## Architecture Traceability

The current requirement, use-case, component, contract, and test matrix lives
in
[Atomic Coherence-Preserving Simplification](housekeeping/atomic-coherence-simplification.md).
The [Evolution Plan](evolution-plan.md) records the broader value-stream model,
and the [Telemetry-First Adoption Map](adoption-map.md) records the current
adoption path and roadmap.
