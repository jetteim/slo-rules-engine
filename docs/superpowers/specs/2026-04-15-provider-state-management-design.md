# Provider State Management Design

**Parent:** Evolution Plan

**Decision:** Use a provider-state framework with Datadog live API support first, manifest-based apply planning for Prometheus-compatible bundles, and external-generator handoff for Sloth.

**Outcome:** Maintainers can move from reviewed SLO intent to managed backend state without making provider generation mutate live systems implicitly.

**Scope:** Include telemetry lookup, provider online sanity checks, apply planning, dry-run, explicit live apply, and architecture rules for future providers. Exclude copying service definitions, backend credentials, internal routing targets, and organization-specific constants from legacy material.

**Architecture impact:** Component-level change inside `slo-rules-engine`: provider metadata expands from artifact capabilities to automation modes; new telemetry lookup and backend state components sit beside provider generation; CLI gains explicit state-management commands that are separate from `generate`.

**Implementation handoff:** `docs/superpowers/plans/2026-04-15-provider-state-management.md`

**Evidence:** Legacy implementation review found reusable public-safe patterns for metric inventory, Thanos/Prometheus validation, Datadog validation, Datadog API apply, dry-run, and prune. Current repo review found generation and static reality checks but no live lookup or applier layer.

## Observability State Pipeline Model

The provider-state workflow borrows the useful shape of observability pipeline tools: explicit sources, transforms, sinks, validation, and test fixtures. It does not copy a streaming DSL or make SLO policy an event-processing program.

Pipeline stages:

- **Sources:** reviewed service definitions, backend telemetry lookup output, generated provider manifests, and imported backend state.
- **Transforms:** telemetry normalization, candidate generation, provider validation, reality checks, and apply-plan calculation.
- **Sinks:** Datadog API, Prometheus-compatible manifest bundle, Sloth external-generator handoff, and route catalog outputs.
- **Findings side path:** unsupported telemetry, missing backend series, missing provider bindings, unsafe live mutation, and unsupported provider state actions.

Validation rules:

- Every source must be explicit and reproducible.
- Every transform must be deterministic for identical inputs.
- Every sink must declare whether it mutates a live backend, writes files, or hands off to another generator.
- Backend mutation must be isolated to sink/applier components.
- Apply plans must be testable with fixture input and fake backend state before any live apply path is trusted.

## Capability Set

### Backend Telemetry To Reviewed SLO Definition

This capability lets a maintainer start with existing telemetry instead of hand-authoring every SLI/SLO. Backend lookup is evidence, not policy. The engine may propose SLI/SLO candidates, but accepted reliability intent remains a reviewed service definition.

Features:

- Backend telemetry lookup adapters normalize provider observations into the existing telemetry inventory shape.
- Datadog lookup checks metric names and time series availability through an injectable HTTP client.
- Prometheus-compatible lookup checks metric names, series presence, instant query results, and histogram bucket availability through an injectable query client.
- Candidate generation accepts either file-based telemetry inventory or lookup output.
- Calculation-basis recommendation uses measured observation rate and error-count-to-alert sensitivity.
- Provider sanity checks report missing bindings, missing metrics, missing time series, missing histogram buckets, and low-volume risk as machine-readable findings.
- Generated drafts remain review drafts and must validate before provider generation.

### Reviewed Manifest To Managed Backend State

This capability manages backend state only after neutral intent has generated reviewable artifacts.

Features:

- Providers declare an `automation_mode`.
- Providers declare supported state actions: `plan`, `apply`, `prune`, `import_existing`, or `diff`.
- `generate` remains read-only and deterministic.
- `apply` is a separate command.
- Dry-run apply emits an apply plan and is safe to run without backend mutation.
- Live apply requires explicit confirmation and provider credentials.
- Provider API clients are injectable so tests do not call live backends.
- Apply output records operation, target, source artifact, and resulting backend identifier when known.
- Prune is separate from apply and must require explicit confirmation.

## Automation Modes

### `live_api`

The provider can use backend APIs directly.

Initial provider:

- `datadog`

Required behavior:

- dry-run apply plan
- explicit live apply confirmation
- credential validation
- retry handling for rate limits and transient server errors
- create or update behavior based on imported backend state
- machine-readable operation results

### `manifest_bundle`

The provider generates files intended for another deployment system.

Initial provider:

- `prometheus_stack`

Required behavior:

- apply plan lists files to write or update
- dry-run reports file paths and resource kinds
- live apply writes deterministic artifact bundles only
- direct Kubernetes, Grafana, or Alertmanager mutation is a future adapter, not implied by this mode

### `external_generator`

The provider generates input for another tool that owns final backend rule expansion.

Initial provider:

- `sloth`

Required behavior:

- apply plan writes Sloth specs and records the external generator command handoff
- no live backend mutation unless a future adapter explicitly runs the external generator and applies its output

## Component View

**Question:** Which components own generation, lookup, validation, and backend mutation?

**Audience:** maintainers and provider contributors.

**C4 level:** component.

### Elements

- Service Definition DSL: captures reviewed provider-independent reliability intent.
- Core Validator: validates neutral model shape and review requirements.
- Provider Registry: resolves provider metadata, generation, validation, and state support.
- Provider Generator: translates accepted intent into deterministic backend artifacts.
- Telemetry Lookup Adapter: queries a backend and returns normalized telemetry inventory.
- Online Provider Validator: uses backend lookup to check metric and series reality.
- Apply Planner: converts generated artifacts and imported backend state into create, update, skip, or delete plans.
- Backend API Client: performs provider-specific HTTP or file operations through injectable transport.
- Applier: executes an apply plan when explicitly confirmed.
- CLI: exposes `generate`, `lookup-telemetry`, `reality-check`, `apply`, `diff`, `import`, and `prune` commands.
- Findings Reporter: emits unsupported, unsafe, missing, or unverified pipeline facts as machine-readable output.

### Relationships

- CLI -> Service Definition DSL: loads reviewed definitions from files.
- CLI -> Telemetry Lookup Adapter: requests backend telemetry evidence.
- Telemetry Lookup Adapter -> Candidate Generator: provides normalized inventory for SLI/SLO proposals.
- Provider Generator -> Apply Planner: provides generated artifacts as desired state.
- Apply Planner -> Backend API Client: imports current state when provider supports it.
- Applier -> Backend API Client: executes confirmed state changes.
- Apply Planner -> Findings Reporter: emits unsupported or unsafe operations instead of dropping them.

### Decisions

- Generation and apply are separate commands.
- Provider automation mode is explicit and testable.
- Provider state management is modeled as a source-to-transform-to-sink pipeline.
- Apply planning is a deterministic transform; live mutation is only a sink action.
- Datadog is the first live API provider.
- Prometheus-compatible output starts as manifest bundle state management.
- Sloth starts as external-generator handoff.
- Future providers must document both artifact generation and backend state behavior before being called production-grade.

### Risks / NFRs

- Backend mutation must be reversible or explicitly confirmed.
- Tests must not require network access.
- Apply logic must never store credentials.
- Private legacy examples must not enter fixtures, docs, commits, or generated artifacts.
- Missing telemetry must become a finding, not a silent pass.

## Feature Packets

### Feature: Provider Automation Contract

**Parent capability:** Reviewed Manifest To Managed Backend State

**Value:** contributors know what a provider can generate, validate, and apply before users trust it.

**Feature type:** platform

**C4 impact:** component

Acceptance criteria:

- Given a provider registry, when providers are listed, then each provider reports `automation_mode` and state actions.
- Given a provider without live API support, when live apply is requested, then the CLI fails with a clear unsupported-action error.
- Given future provider docs, when a contributor reads the contract, then generation, validation, reality-check, and apply obligations are explicit.

### Feature: Datadog Live API Applier

**Parent capability:** Reviewed Manifest To Managed Backend State

**Value:** Datadog users regain the ability to apply reviewed SLO artifacts through API calls instead of manually copying generated JSON.

**Feature type:** operational

**C4 impact:** component

Acceptance criteria:

- Given generated Datadog artifacts, when dry-run apply is requested, then the CLI emits create/update operations without calling Datadog.
- Given generated Datadog artifacts and explicit confirmation, when live apply is requested, then the Datadog client creates or updates SLOs, monitors, telemetry-gap monitors, and dashboards.
- Given missing credentials, when live apply is requested, then the CLI fails before any HTTP request.
- Given Datadog returns rate limiting or transient server errors, when live apply runs, then the client retries according to the retry policy.

### Feature: Provider Manifest Bundle Appliers

**Parent capability:** Reviewed Manifest To Managed Backend State

**Value:** providers without safe live API support still participate in the same apply workflow as deterministic managed outputs.

**Feature type:** platform

**C4 impact:** component

Acceptance criteria:

- Given Prometheus-compatible generated artifacts, when apply is run, then output files are written through the provider apply contract.
- Given Sloth generated specs, when apply is run, then specs are written and the external generator handoff is recorded.
- Given a provider with `manifest_bundle` or `external_generator`, when live backend mutation is requested, then the provider refuses unless it has a dedicated adapter.

### Feature: Backend Telemetry Lookup And Sanity Checks

**Parent capability:** Backend Telemetry To Reviewed SLO Definition

**Value:** maintainers can generate SLI/SLO candidates and validate definitions against real backend telemetry evidence.

**Feature type:** operational

**C4 impact:** component

Acceptance criteria:

- Given a Datadog metric lookup request, when the backend returns metric or series data, then the engine emits normalized telemetry inventory.
- Given a Prometheus-compatible lookup request, when the backend returns metric, series, or query data, then the engine emits normalized telemetry inventory.
- Given a reviewed definition, when online sanity checks run, then missing metrics, missing series, invalid histogram buckets, and calculation-basis risks are reported as findings.
- Given lookup output, when `draft-definition` consumes it, then generated draft definitions remain loadable and validate through the same core validation path.

## Future Provider Rules

Every provider contribution must state:

- Provider role: backend bundle, manifest bundle, external generator, delivery integration, or interchange export.
- Generation artifacts.
- Reality-check mechanism.
- Telemetry lookup mechanism, or a documented reason it is unsupported.
- Apply mode and supported state actions.
- Credential requirements for live mutation.
- Dry-run behavior.
- Import/diff/prune behavior or explicit unsupported findings.
- Public-safe fixtures proving generation and apply planning.

## Out Of Scope For First Implementation Slice

- Live Kubernetes apply.
- Live Grafana API apply for Prometheus-compatible dashboards.
- Running Sloth CLI.
- Pruning live Datadog resources.
- Importing private service inventory.
- Copying legacy service definitions or backend constants.
