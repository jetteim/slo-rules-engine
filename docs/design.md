# Design

## Architecture

The engine is a local Ruby application with explicit boundaries around neutral
reliability intent, provider translation, reviewed evidence, state execution,
and read-only status. Phase 14 now includes Human dispatch, Agent runtime
introspection, and typed structured invocation for seven commands; later Agent
commands and MCP must reuse the same application behavior.

```text
Operator / CI            AI agent                 MCP client (planned)
  |                         |                         |
Human CLI adapter      Agent CLI adapter        MCP stdio adapter
  |                         |                         |
  +------------- versioned command registry --------+
                            |
             typed application commands
                            |
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
telemetry, reports, release bundles, journals, approved plans, Sloth downstream
evidence, and live status.
Shared manifest/state orchestration remains in the library facade because those
commands intentionally share definition loading, provider validation, review
freshness, error rendering, and usage behavior.

### Command Contract And Agent Interfaces

The [Agent Interface Roadmap](agent-interface-roadmap.md) introduced one
versioned command registry between interface adapters and current handlers.
AICLI-F1 now implements `CommandDefinition`, `CommandRegistry`, and the separate
`CommandCatalog` parity entity. The registry validates 40 immutable command
definitions and drives current Human top-level and grouped-subcommand dispatch.
The catalog pairs each executable Human command example with its target
versioned Agent JSON request. `AgentIntrospection` resolves strict request
schemas from that metadata and serves bounded offline catalog/describe output
through the focused `AgentCommands` adapter.

The Human CLI adapter preserves existing positional/convenience syntax. The
Agent adapter validates complete JSON requests and returns stable result/error
envelopes for seven registry-mapped application commands. Analysis commands
use bounded workspace-contained `.rb` inputs; file-backed `diff` additionally
uses a reviewed `.json` manifest and confined managed root, with no provider
network or writes. Application stdout/stderr and direct exits are quarantined.
Field projection, collection limits, remaining output/URL/ID hardening,
validation-only behavior, sanitization, skill guidance, and MCP schemas must
derive from this foundation.

The registry is an orchestration contract, not a second policy layer. It cannot
override neutral intent, provider validation, reviewed evidence, ownership,
exact-plan, confirmation, journal, or verification requirements.

The measured dependency debt, target direction, eight reversible refactoring
packets, freeze zones, and all-use-case preservation matrix are in the
[Project Structure Refactoring Plan](housekeeping/project-structure-refactoring-plan.md).
STR-0 must make current boundary exceptions visible and reject new edges before
the larger decomposition packets start.

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

`live_status.rb`, `live_status/sloth_reader.rb`, and
`live_status/aggregate.rb` read generated Prometheus record identities and
normalize objective, budget, burn, freshness, and coverage. Prometheus Stack
reads identifiers from its reviewed manifest. Sloth first validates an exact,
fresh downstream-evidence artifact and then reads only its status bindings.
Provider query syntax remains evidence in the reader. Live status never mutates
provider state and never persists runtime endpoints.

### Sloth Downstream Evidence

`sloth/downstream_evidence.rb` owns the provider-specific bridge between one
reviewed Sloth manifest/native input set and externally generated Prometheus
rule YAML. It parses JSON and safe YAML structurally, validates complete
per-SLO generated record identity and reviewed objective/budget agreement,
persists a content-addressed reviewer attestation, and rechecks canonical
source fingerprints without executing Sloth or contacting Prometheus.

The artifact retains generated record selectors and the reviewed native total
query as provider evidence. It does not add PromQL to the neutral model. The
direct Sloth reader now explicitly accepts it; release-bundle verification and
aggregate status do not yet package it.

`sloth/mcp.rb`, `sloth/mcp/client.rb`, and `sloth/mcp/comparison.rb` own the
implemented provider-runtime comparison adapter for Sloth's official HTTP MCP
server. They preflight exact downstream evidence, pin protocol/version/tool
schemas, bound provider reads, reconcile exact identities, and emit a
non-authoritative comparison artifact without persisting the runtime endpoint.
This boundary is not the planned engine MCP interface and cannot bypass
downstream evidence or promote neutral status. The engine's AICLI-F6 MCP server
remains a registry-generated command adapter with no independent provider logic.

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
reviewed Prometheus Stack manifest or reviewed Sloth manifest + fresh evidence
  -> generated recording-rule identities / evidence status bindings
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
- Human CLI, Agent CLI, and MCP adapters depend on the command registry and
  shared handlers; adapters must not call provider collaborators directly.
- Command schema, side-effect metadata, skill guidance, and MCP tool metadata
  must not become independent sources of truth.
- `CommandCatalog` is the compact Human-command to Agent-JSON parity view;
  `CommandRegistry` remains the validated resolver and full metadata source.
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
- Agent requests are untrusted: strict schemas, field-specific path/ID/URL
  validation, size limits, and side-effect classification precede handlers.
- Agent output is bounded, projectable, explicitly truncated or streamed, and
  sanitizes provider-controlled free text before exposure.
- `validate_only` performs no file/provider I/O; observational plans that read
  state remain separately declared.
- Public-safe terminology and fixtures are enforced by the verification suite.

## Architecture Traceability

The current requirement, use-case, component, contract, and test matrix lives
in
[Atomic Coherence-Preserving Simplification](housekeeping/atomic-coherence-simplification.md).
The [Evolution Plan](evolution-plan.md) records the broader value-stream model,
and the [Telemetry-First Adoption Map](adoption-map.md) records the current
adoption path and roadmap. Phase 14 intent, requirements, parity, and target
interfaces live in the [Agent Interface Roadmap](agent-interface-roadmap.md).
The [Project Structure Refactoring Plan](housekeeping/project-structure-refactoring-plan.md)
records the current structural baseline and requirements-preserving execution
order.
