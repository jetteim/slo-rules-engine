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

Confirmed apply/prune for every current provider emits this value under
`execution.result`. Datadog operation results carry returned or existing
backend IDs; Prometheus Stack and Sloth carry managed paths as provider resource
identifiers. The plan's observed-state fingerprint still identifies the
pre-execution snapshot. Post-operation verification separately records
expected and actual provider/file state fingerprints, timestamps, per-resource
status, and findings.

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
`resume_blocked`, or `resume_state_recheck_required` findings. It rejects
terminal states without matching attempt evidence, non-sequential attempts,
invalid timestamps, static-identity tampering, and credential-like keys.

`journal create` verifies the saved provider-state snapshots and plan
fingerprint before writing the initial journal atomically. Recreating the same
journal at the same path is idempotent. Existing different content is never
overwritten.

Confirmed apply/prune uses `JournalStore` and requires `--journal-dir`. The
store:

- creates one live-mode journal before the first mutation
- serializes transitions with an exclusive journal lock
- replaces journal JSON atomically after every transition
- permits `pending` to `running` to `succeeded` or `failed`
- permits an unstarted operation to become `skipped`
- rejects competing or terminal-state transitions
- refuses to replace an existing journal with execution evidence; an identical
  all-`skipped` noop journal is reused safely

Execution stops after the first failed operation. Later actionable entries
become `skipped` with `prior_operation_failed`; the result becomes `failed` or
`partial` and the CLI exits nonzero.

Datadog successful attempts record the request method/path, returned or
existing backend identifier, response fingerprint, response top-level keys,
and completion timestamp. Raw API responses and backend error messages are not
persisted. After attempts finish, the engine refreshes backend state once:

- apply compares canonical desired and actual payload plus provider identity
- prune compares each recorded provider ID with the refreshed managed scope and
  requires absence
- stable findings distinguish missing resources, identity mismatch, payload
  drift, surviving deletes, and refresh failure
- a verification failure adds `post_apply_verification_failed` and makes an
  otherwise successful result and CLI exit fail

Successful file write/delete attempts record the managed path, byte/delete
evidence, and completion timestamp.

After operation attempts finish, every attempted engine-owned file is refreshed
from disk:

- writes compare canonical parsed JSON/YAML content with the live plan
- deletes compare expected and actual absence
- terminal evidence records a check timestamp, path, expected state
  fingerprint, actual state fingerprint, and stable findings
- verification failures add `post_apply_verification_failed`; a fully executed
  plan with drift produces a failed result and nonzero CLI exit
- operation failures still retain `failed` or `partial` execution status while
  verification identifies every attempted resource that did not converge
- `noop` entries remain `not_required` because the live plan already observed
  matching state immediately before execution

Sloth's external-generator handoff is not executed. Its entry becomes
`skipped` with `external_handoff_required` after engine-owned files are written.
The manifest and native inputs can reach `engine_owned_status: succeeded`, but
overall and external verification stay `pending` until downstream generation
and Prometheus state are verified outside the engine.

### Approved Provider Plan

Exact file-backed execution uses a separate approval schema:

```text
slo-rules-engine/approved-provider-plan/v1
```

The document locks one `apply_ready` release-bundle target together with:

- reviewer identity, explicit approval timestamp, and notes
- source release-bundle identity
- bundle review content and fingerprint
- provider manifest, manifest-review report, reviewed handoff, and generated
  change-plan artifact fingerprints
- the validated `dry_run` provider-state plan
- its desired-state and observed-state fingerprints
- a managed output directory derived from contained operation paths

Approval is content-addressed and credential-free. `plan status` revalidates
the document and every nested provider-state fingerprint without reading
managed state.

Exact apply acquires one nonblocking lock for the managed service/provider
scope, replans only to compare immediate state with the approved plan, and
discards the regenerated operations. It reconstructs the live `ApplyPlan` from
the approved changes. Managed-state drift returns `stale_approved_plan`;
same-scope concurrency returns `approved_plan_scope_busy`.

The live journal's plan reference includes the approved-plan ID, approved
dry-run plan fingerprint, source bundle ID, and aggregate approval-evidence
fingerprint. Journal identity covers that reference. Prometheus Stack and
Sloth retain the existing post-operation verification rules; Sloth's stored
handoff remains skipped and pending.

A completed exact plan can be replayed idempotently only when an immediate
managed-state read proves all engine-owned changes are `noop`. The existing
journal and `ProviderStateResult` are returned without new attempts or file
writes. Drift still returns `stale_approved_plan`. Partial and failed journals
return `approved_plan_requires_resume` and keep their attempt history
unchanged; the failed result includes state-recheck and manual rollback
guidance.

`plan resume` is an explicit mutation boundary. It requires the same approved
plan, journal directory, confirmation, and managed-scope lock. Before any new
attempt it validates operation identity and proves every previously successful
write still converges. Only `write` entries with journal resume eligibility may
start another attempt; skipped writes with `prior_operation_failed` may start
their first attempt. Current `noop` state is recorded as reconciled by the
state recheck without rewriting. Terminal verification evidence is then
replaced with a fresh full managed-file recheck.

## Provider Evidence

### Datadog

Plan and diff:

- desired snapshot: reviewed Datadog provider manifest
- observed snapshot: current matched API state
- changes: translated API payloads, backend IDs, changed paths, match identity, and risk

Import:

- observed snapshot: current matched API state
- findings: missing expected resources, managed orphans, and weak identity
- dashboard evidence: paginated custom-dashboard summaries followed by full
  detail reads for managed tags, source identity, and canonical payload

Prune:

- observed snapshot: service-scoped managed backend state
- changes: managed orphan deletes with provider resource IDs, ownership confidence, and risk
- dashboard scope: all custom dashboards with matching engine/service tags,
  independent of manual dashboard-list membership

### Prometheus Stack

Plan and diff:

- desired snapshot: reviewed Prometheus Stack manifest including rendered native resources
- observed snapshot: managed-file entries with path, presence, and current resource content
- changes: manifest, PrometheusRule, Grafana ConfigMap, and Alertmanager route-intent file operations

Import:

- observed snapshot: managed manifest and every expected native resource file
- findings: missing manifest or native bundle files

Confirmed apply and prune:

- durable journal required before mutation
- managed JSON/YAML paths recorded as successful resource identifiers
- per-operation write/delete attempts and failure evidence
- `ProviderStateResult` linked to the immediate live plan
- terminal expected/actual presence and canonical content fingerprints for
  every attempted managed path

### Sloth

Plan and diff:

- desired snapshot: reviewed Sloth manifest and native spec intent
- observed snapshot: managed manifest and native input file entries
- changes: manifest and native input file operations plus external-generator handoff

Import:

- observed snapshot: managed manifest and every expected native Sloth input
- findings: missing manifest or external-generator input files

The provider-state transition does not execute the Sloth CLI or claim
downstream generated Prometheus state as its observed Sloth state. A later
read-only `bundle verify` transition may separately attach current reviewed
downstream evidence and a runtime, then record the complete neutral live-status
report without rewriting the provider-state result.

Confirmed Sloth apply/prune uses the same managed-file journal/result contract
as Prometheus Stack. Apply records the external generator as an intentionally
skipped handoff rather than claiming downstream execution.

## Safety And Compatibility

- State values are immutable after construction.
- Snapshot fingerprints are derived from canonicalized content.
- Provider and service identity must match across plan/import envelopes and snapshots.
- Provider-specific payloads, resource IDs, identity confidence, and risk remain intact.
- Credentials and credential-like keys are forbidden in journals.
- Existing review and ownership gates remain in force; every confirmed
  apply/prune additionally requires `--journal-dir`.
- Release-bundle plans now package the state contract inside each generated change-plan artifact.
- Approved-plan output is idempotent for identical content and refuses
  conflicting output without overwrite.
- Exact file-backed execution rejects immediate state drift and serializes
  concurrent execution for the same managed scope.
- Journal creation accepts exactly one `dry_run` plan and revalidates all
  content fingerprints before persistence.
- Journal identity excludes mutable entry status and attempts while covering
  provider, service, plan, operation, resume-policy, and verification identity.
- Journal commands do not contact providers or managed-file targets.
- Journal entry transitions and attempt evidence do not change journal
  identity.
- Datadog verification covers supported managed payload/identity semantics and
  delete absence. File-backed verification covers only engine-owned managed
  paths. Neither claims notification delivery, Kubernetes, Grafana,
  Alertmanager receiver, Sloth execution, or downstream Prometheus mutation.
  Evidence-backed release verification can separately prove that reviewed
  Sloth-generated state is readable and complete through GET-only queries.

## Not Yet Implemented

- Datadog or non-resumable operation retry after partial failure
- automatic downstream Sloth execution, rule reload, or provider mutation
- automatic compensating rollback plans
- Datadog approved-plan execution and live backend recheck

Those features must build on this contract rather than overloading the current dry-run plan.
