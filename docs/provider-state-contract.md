# Provider State Contract

The provider-state contract gives Datadog, Prometheus Stack, Sloth, release bundles, and future execution workflows one versioned vocabulary without moving provider payload or safety policy into the neutral layer.

Schema version:

```text
slo-rules-engine/provider-state/v1
```

## Contract Values

### Desired State

`ProviderDesiredState` records:

- provider and service identity
- source, currently `provider_manifest`
- immutable provider-owned resources
- deterministic SHA-256 content fingerprint

The resources remain provider-shaped. A Datadog manifest is not flattened into a Kubernetes file model, and a PrometheusRule is not translated into a Datadog payload.

### Observed State

`ProviderObservedState` records:

- the same provider and service identity
- observation source
- immutable provider-owned observed resources
- deterministic SHA-256 content fingerprint

Current sources include:

- `backend_api` for Datadog matched state
- `managed_backend_scope` for Datadog prune discovery
- `manifest_bundle` for Prometheus Stack and file-backed plan/diff evidence
- `external_generator_files` for Sloth import evidence

No collection timestamp is inferred. A later caller that needs time-bounded evidence must provide and contract that metadata explicitly.

### Change

`ProviderStateChange` projects one existing provider operation into shared fields:

- action
- resource target
- provider resource name
- source artifact identity
- desired provider payload
- observed provider payload
- changed paths
- provider resource ID
- match-identity evidence
- provider-owned risk evidence

Supported actions currently include `create`, `create_and_wait`, `update`, `recreate`, `recreate_and_wait`, `delete`, `noop`, `write`, and `handoff`.

### Finding

`ProviderStateFinding` records:

- provider
- stable code
- severity: `finding`, `warning`, or `error`
- message
- optional path, target, and source
- provider-specific evidence not represented by the common fields

Current provider findings default to `finding`. This does not weaken existing mutation gates; Datadog ownership and payload errors still stop in their provider-specific enforcement paths.

### Plan And Import

`ProviderStatePlan` ties together:

- desired and observed snapshots
- shared changes
- normalized findings
- existing operation impact summary
- provider, service, and plan mode
- deterministic plan fingerprint derived from desired, observed, change, finding, and summary evidence

`ProviderStateImport` ties desired and observed snapshots to normalized import findings.

Existing `ApplyPlan#to_h` and `ImportedState#to_h` fields remain available. The versioned contract is added under `state_contract`, allowing current consumers to migrate without losing the existing `operations`, `state`, or raw `findings` shapes.

### Result

`ProviderStateResult` defines the execution-result boundary:

- provider, service, and mode
- status: `succeeded`, `partial`, `failed`, `noop`, or `blocked`
- desired and observed state fingerprints
- provider-state plan fingerprint
- per-operation results
- findings
- verification evidence

The value contract exists, but current apply commands do not emit it yet.

### Operation Journal

The durable initial journal uses a separate lifecycle schema:

```text
slo-rules-engine/provider-operation-journal/v1
```

`ProviderOperationJournal` records:

- deterministic journal ID
- provider and service identity
- provider-state plan fingerprint
- desired-state and observed-state fingerprints
- one ordered entry per normalized provider change
- initial journal status and entry-state summary
- non-resumable-operation findings

Journal entry states are `pending`, `running`, `succeeded`, `failed`, and
`skipped`. Initial actionable entries are `pending`; `noop` entries are
`skipped`.

Each entry preserves the provider change payload, changed paths, resource ID,
match identity, and risk evidence. It also records:

- whether retry may be considered
- whether provider or managed-file state must be refreshed first
- a conservative resume classification
- provider-specific verification requirements
- an initially empty attempt list

Current resume classification is deliberately conservative:

- `update` and `write` may be retried only after state recheck
- `create`, `create_and_wait`, `recreate`, `recreate_and_wait`, `delete`, and
  `handoff` require manual verification after an uncertain failure
- `noop` requires no execution

`JournalEvaluator` derives effective `pending`, `running`, `succeeded`,
`partial`, or `failed` state from entries and reports `partial_failure`,
`resume_blocked`, or `resume_state_recheck_required` findings. This is an
assessment contract only; current commands do not write execution transitions.

`journal create` verifies the saved provider-state snapshots and plan
fingerprint before writing the initial journal atomically. Recreating the same
journal at the same path is idempotent. Existing different content is never
overwritten.

## Provider Evidence

### Datadog

Plan and diff:

- desired snapshot: reviewed Datadog provider manifest
- observed snapshot: current matched API state
- changes: translated API payloads, backend IDs, changed paths, match identity, and risk

Import:

- observed snapshot: current matched API state
- findings: missing expected resources, managed orphans, and weak identity

Prune:

- observed snapshot: service-scoped managed backend state
- changes: managed orphan deletes with provider resource IDs, ownership confidence, and risk

### Prometheus Stack

Plan and diff:

- desired snapshot: reviewed Prometheus Stack manifest including rendered native resources
- observed snapshot: managed-file entries with path, presence, and current resource content
- changes: manifest, PrometheusRule, Grafana ConfigMap, and Alertmanager route-intent file operations

Import:

- observed snapshot: managed manifest and every expected native resource file
- findings: missing manifest or native bundle files

### Sloth

Plan and diff:

- desired snapshot: reviewed Sloth manifest and native spec intent
- observed snapshot: managed manifest and native input file entries
- changes: manifest and native input file operations plus external-generator handoff

Import:

- observed snapshot: managed manifest and every expected native Sloth input
- findings: missing manifest or external-generator input files

The engine does not execute the Sloth CLI or claim downstream generated Prometheus state as observed Sloth state.

## Safety And Compatibility

- State values are immutable after construction.
- Snapshot fingerprints are derived from canonicalized content.
- Provider and service identity must match across plan/import envelopes and snapshots.
- Provider-specific payloads, resource IDs, identity confidence, and risk remain intact.
- Credentials are not part of the state contract.
- Existing apply, prune, and ownership gates are unchanged.
- Release-bundle plans now package the state contract inside each generated change-plan artifact.
- Journal creation accepts exactly one `dry_run` plan and revalidates all
  content fingerprints before persistence.
- Journal identity excludes mutable entry status and attempts while covering
  provider, service, plan, operation, resume-policy, and verification identity.
- Journal commands do not contact providers or managed-file targets.

## Not Yet Implemented

- live execution writes to operation journals
- automatic operation-state transitions
- actual resume execution after partial failure
- post-apply observed-state refresh and verification result emission
- compensating rollback plans
- exact execution of a separately reviewed plan
- concurrent-apply protection

Those features must build on this contract rather than overloading the current dry-run plan.
