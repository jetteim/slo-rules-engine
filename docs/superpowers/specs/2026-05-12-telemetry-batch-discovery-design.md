# Telemetry Batch Discovery Design

**Parent:** Adoption Map

**Decision:** Add `discover-telemetry --scope-file` as the first telemetry-first expansion, with one provider per run, persisted per-scope discovery evidence, and a shared normalized output contract that later ranking, candidate generation, and draft-definition flows can consume without provider-specific parsing.

**Outcome:** Maintainers can point the engine at a portfolio of service or selector scopes, capture reusable discovery evidence for each scope in one run, and use those saved results as the foundation for review-readiness ranking, candidate confidence, and draft generation.

**Scope:** Include the batch discovery CLI path, scope-file schema, persisted result format, aggregate index output, validation rules, provider telemetry interface requirements, contributor-guide requirements, and backlog updates. Exclude provider-backed scope enumeration, service ranking, candidate-confidence scoring, and automatic draft generation from the batch command itself.

**Architecture impact:** Component-level change inside `slo-rules-engine`: the telemetry lookup layer gains a batch-orchestration entrypoint in the CLI; normalized discovery results become persisted evidence artifacts; provider documentation and contribution requirements expand to include the telemetry discovery and lookup interface as part of the provider contract.

**Implementation handoff:** A separate implementation plan document will be written only after this spec is reviewed and approved.

**Evidence:** Current repo review shows `discover-telemetry` supports one scope per invocation, `lookup-telemetry` and `discover-telemetry` already normalize results to `provider`, `signals`, and `findings`, and onboarding commands already consume normalized telemetry envelopes. The largest telemetry-first gap is not single-scope discovery itself; it is the lack of a portfolio-scale evidence capture path.

## Problem

The repo already supports:

- single-scope provider discovery;
- normalized signal and finding envelopes;
- candidate generation from normalized telemetry;
- draft-definition generation from normalized telemetry.

What it does not support is the operational starting point the roadmap now prioritizes:

- discover many scopes in one pass;
- preserve one saved evidence file per scope;
- produce an aggregate index that later stages can rank and revisit without rerunning backend lookups.

Without that batch evidence capture step, maintainers still have to glue together repeated CLI calls manually before the repo can act like a telemetry-first onboarding engine.

## Design Summary

The first telemetry-first slice extends `discover-telemetry` rather than creating a new top-level command.

The new path uses a scope file as the primary batch input. One run targets one provider. The CLI loads the scope entries, validates them against provider scope rules, executes provider discovery once per scope, writes one normalized result file per scope, and writes one aggregate `index.json` file that summarizes the run.

This design keeps the first slice small:

- it reuses existing provider adapters;
- it reuses the current normalized discovery result envelope;
- it does not introduce multi-provider execution in one run;
- it does not introduce automatic backend enumeration yet;
- it produces reusable evidence for later ranking and onboarding stages.

## CLI Contract

The existing command stays the entrypoint:

```bash
bin/rules-ctl discover-telemetry \
  --provider=<provider> \
  --scope-file=<scopes.json> \
  --output-dir=<dir> \
  [--base-url=<url>] \
  [--from=<ts>] \
  [--to=<ts>]
```

### Rules

- `--scope-file` is mutually exclusive with `--service`, `--selector`, and `--host`.
- `--output-dir` is required when `--scope-file` is present.
- one provider per run only.
- existing single-scope behavior remains valid when `--scope-file` is absent.

### Behavior

- for each scope entry, the CLI calls the existing provider adapter `discover(...)`;
- the CLI writes one saved result file per scope;
- the CLI writes one aggregate `index.json`;
- stdout prints the aggregate run summary, not the full contents of every saved result file.

## Scope File Schema

The first slice supports a minimal, provider-neutral schema:

```json
[
  {
    "label": "checkout-prod",
    "service": "checkout-api",
    "selectors": {
      "env": "prod"
    }
  },
  {
    "label": "payments-prod",
    "selectors": {
      "team": "payments",
      "env": "prod"
    }
  }
]
```

### Supported fields

- `label` optional stable output name
- `service` optional service scope
- `selectors` optional selector map
- `host` optional Datadog-only scope

### Validation rules

- each entry must define at least one of: `service`, `selectors`, `host`
- `selectors` must be a string-to-string map
- `label`, when present, must be filesystem-safe after normalization
- duplicate normalized labels must fail explicitly
- Datadog host discovery must not combine `host` with `service` or `selectors`
- non-Datadog providers must reject `host`

The schema intentionally does not support per-entry provider selection in the first slice.

## Result Contract

The batch path preserves the existing normalized discovery envelope and adds scope metadata around it.

### Per-scope result file

Each saved file must be valid onboarding evidence without provider-specific postprocessing. It should contain:

- `provider`
- `scope`
- `signals`
- `findings`

Recommended shape:

```json
{
  "provider": "datadog",
  "scope": {
    "label": "checkout-prod",
    "service": "checkout-api",
    "selectors": {
      "env": "prod"
    }
  },
  "signals": [],
  "findings": []
}
```

This keeps the result directly reusable by later ranking, `candidates`, `draft-definition`, and reality-check flows.

### Aggregate index output

The aggregate `index.json` records run-level summary and file references:

- `provider`
- `generated_at`
- `total_scopes`
- `successful_scopes`
- `failed_scopes`
- `scopes`

Each `scopes` entry should include:

- `label`
- `scope`
- `status`
- `result_file`
- `signal_count`
- `finding_count`
- optional `error` object when discovery failed for that scope

This aggregate file is the future handoff point for service review-readiness ranking.

## Provider Interface Requirements

The provider telemetry interface becomes an explicit part of the provider contract.

### Required adapter surface

Providers that support telemetry evidence must continue to expose:

- `lookup(metric:, kind:, user_visible:, query: nil)`
- `discover(service: nil, selectors: {}, host: nil)`

Both methods must return normalized `TelemetryLookup::Result` objects.

### Discovery obligations

A discovery-capable provider must document:

- supported scope inputs
- unsupported scope combinations
- provider-specific restrictions, such as Datadog host-vs-tag-scope rules
- normalized result semantics
- failure and finding semantics
- whether batch discovery is supported through the shared CLI contract

### Lookup obligations

A lookup-capable provider must document:

- supported explicit metric and query lookup behavior
- missing-series and missing-query-result behavior where relevant
- credential requirements for online lookups
- normalized output shape

### Shared contract

Provider discovery and lookup output must be reusable by later onboarding stages without provider-specific parsing or transformation. Backend-specific payload details stay inside provider adapters.

## Documentation And Guide Updates

This slice must explicitly update the documentation surface, not only code.

### Provider contract updates

`docs/provider-contract.md` must state:

- the telemetry discovery and lookup adapter interface;
- the normalized evidence contract for batch and single-scope discovery;
- the requirement that provider output be reusable by later onboarding stages;
- provider-specific scope constraints as part of the production-grade provider contract.

### Provider contribution guide updates

`docs/provider-contribution-guide.md` must state:

- required telemetry adapter methods;
- expected normalized result objects;
- required negative-path tests for invalid scopes and unsupported combinations;
- batch-discovery compatibility expectations for discovery-capable providers;
- the rule that discovery evidence is review input, not automatic policy.

### Backlog updates

The running backlog and adoption plan must make the telemetry-first sequence explicit:

1. `--scope-file` batch discovery
2. service portfolio review-readiness ranking
3. candidate confidence and explanation
4. saved evidence packets and handoff state
5. provider-backed scope enumeration using the same saved-evidence contract

## Future Follow-on: Provider-Backed Enumeration

This first slice does not enumerate scopes from the backend.

The next telemetry-first feature after batch discovery should add provider-backed scope enumeration that emits the same scope-file-compatible and saved-evidence-compatible structures. That preserves the batch discovery contract instead of creating a parallel onboarding path.

Enumeration is deferred because:

- it is more provider-specific;
- it introduces service grouping heuristics;
- it is not required to unlock reusable portfolio discovery evidence.

## Acceptance Criteria

### Feature: Batch Discovery By Scope File

**Parent capability:** Service Portfolio Discovery To Review Queue

**Value:** maintainers can gather reusable telemetry evidence for many scopes in one run.

Acceptance criteria:

- Given `--scope-file` and `--output-dir`, when batch discovery runs, then the CLI executes one provider discovery call per scope and writes one result file per scope plus one aggregate `index.json`.
- Given a scope file with duplicate normalized labels, when discovery runs, then the CLI fails with explicit validation output.
- Given `--scope-file` plus single-scope flags, when discovery runs, then the CLI fails with explicit conflict output.
- Given provider-specific scope violations, when discovery runs, then the CLI fails or records the violation explicitly according to the command’s error contract.

### Feature: Reusable Discovery Evidence

**Parent capability:** Service Portfolio Discovery To Review Queue

**Value:** later onboarding stages can consume saved discovery evidence without rerunning backend lookups.

Acceptance criteria:

- Given a saved per-scope discovery file, when later onboarding stages read it, then they can consume the normalized `signals` and `findings` without provider-specific parsing.
- Given an aggregate `index.json`, when a later ranking stage is added, then it can locate per-scope evidence files and their signal/finding counts directly.

### Feature: Provider Telemetry Interface Documentation

**Parent capability:** Service Portfolio Discovery To Review Queue

**Value:** future providers implement discovery and lookup consistently.

Acceptance criteria:

- Given the provider contract, when a contributor reads it, then telemetry lookup and discovery interfaces, normalized result shape, and scope constraint requirements are explicit.
- Given the provider contribution guide, when a contributor adds a provider, then required telemetry adapter methods and negative-path tests are explicit.

## Test Strategy

The first implementation slice should add:

- CLI tests for `--scope-file` conflicts and validation
- scope file schema validation tests
- per-scope output file tests
- aggregate index output tests
- provider constraint tests in batch mode
- fixture-backed tests proving saved results remain normalized onboarding evidence

No live backend calls are required for this slice.

## Risks

- Scope-file format could grow into a provider-specific configuration blob if not constrained. The first slice avoids that by keeping one provider per run and only minimal scope fields.
- Batch output can become a dead-end if the saved files are not directly reusable later. The design avoids that by preserving the normalized discovery envelope.
- Enumeration could pressure the design into provider-specific service modeling too early. The design defers enumeration until the saved-evidence contract exists.

## Out Of Scope

- mixed-provider scope files
- automatic provider-backed scope enumeration
- service review-readiness scoring
- candidate confidence computation
- automatic draft generation from aggregate index runs
- live provider-state changes
