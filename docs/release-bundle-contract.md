# Release Bundle Contract

The first-class release bundle is a self-contained, versioned JSON document that packages reviewed onboarding evidence and provider delivery artifacts. Bundle creation and file-backed planning require no backend calls; live API planning reads current provider state but never mutates it. File-backed bundle verification rereads managed files but never writes them or invokes an external generator.

## Identity

Schema version:

```text
slo-rules-engine/release-bundle/v1
```

Kind:

```text
SLOReleaseBundle
```

`bundle_id` is `slo-bundle-` followed by a SHA-256 digest. Its identity input includes:

- schema version
- reviewer attestation and per-scope decisions
- sorted provider targets and artifact references
- sorted packaged release-artifact fingerprints
- deterministic lifecycle-transition metadata when the bundle was derived by `bundle plan`, `bundle apply`, or `bundle verify`
- generated-artifact lineage metadata

Local file source paths, lifecycle state, findings, summaries, and the onboarding artifact-index fingerprint do not define bundle identity. Rebuilding from unchanged release content, review metadata, and planning evidence produces the same ID.

## Lifecycle

Supported persisted lifecycle states:

- `incomplete`: a required predecessor artifact, review decision, or plan contract is missing or invalid
- `review_ready`: discovery, handoff, reviewed definition, provider manifest, and fresh manifest-review evidence are packaged
- `apply_ready`: every provider target also has a valid dry-run change plan
- `stale`: current review evidence no longer matches its predecessor artifacts
- `applied`: every file-backed target has terminal exact-execution evidence
- `verified`: every file-backed target has fresh converged engine-owned state evidence; Sloth downstream generation may remain explicitly pending

`bundle status` will report `invalid` as an effective status when the schema, an embedded artifact fingerprint, or the content-addressed bundle identity has been tampered with. `invalid` is not a persisted lifecycle state.

## Packaged Artifacts

The v1 artifact inventory supports:

- onboarding artifact index
- aggregate discovery index
- per-scope discovery evidence
- reviewed handoff packet
- reviewed Ruby definition
- provider manifest
- provider-level manifest-review report
- optional current reviewed Sloth downstream-evidence artifact
- optional dry-run provider change plan
- generated target execution result
- generated target verification result

Each artifact includes a stable UID, kind, content type, SHA-256 fingerprint,
source metadata, and embedded content. File-backed predecessors record an
absolute source path. Bundle-native plans and execution results record generated
lineage to the predecessor bundle and provider target instead of inventing a
mutable source file. Provider targets reference the packaged manifest, review
report, optional Sloth downstream evidence, optional plan, applied execution
result, and fresh target verification result by UID. A Sloth evidence reference
must point to a `sloth_downstream_evidence` artifact for that target's provider.

The bundle excludes credential ownership. Structured content containing credential-like keys such as `api_key`, `app_key`, `secret`, `password`, `token`, `authorization`, or `credentials` is rejected before it can be packaged.

## Review Evidence

Bundle creation requires:

- an explicit reviewer identity
- an explicit ISO 8601 review timestamp
- reviewed handoff decisions for every scope
- at least one accepted candidate per scope
- current provider manifest provenance
- a valid and fresh provider-level manifest-review report

Accepted and rejected candidate IDs plus review notes are copied from the reviewed handoff packet. The reviewer identity and timestamp attest the release bundle assembly; they are never inferred from the local clock.

## Planning

`bundle plan` accepts exactly one valid `review_ready` bundle. Before invoking any provider planner it rechecks:

- schema and content-addressed bundle identity
- every embedded artifact fingerprint
- every file-backed source fingerprint
- persisted findings and effective lifecycle
- explicit runtime configuration for every packaged target

The command creates a new `apply_ready` bundle with a new content-addressed ID, a transition reference to its predecessor, one generated dry-run plan per target, and provider-level operation and risk summaries. Each generated plan includes the versioned `slo-rules-engine/provider-state/v1` desired-state, observed-state, change, finding, and plan fingerprints. It never edits the predecessor bundle.

File-backed providers require a per-target managed output directory. Planning reads that directory to distinguish `write` from `noop` but does not create, update, or delete files. Live API providers require the explicit `environment` backend mode; credentials stay in the environment and never enter the bundle. Their planning path may read current backend state but does not invoke provider mutations.

Provider summaries include target and plan counts, total and actionable operations, destructive operations, risky operations, highest risk, and counts by action, resource target, and risk level. Risk classification remains provider-owned.

## Target Approval And Exact File Execution

`plan approve` derives one immutable target approval from a valid
`apply_ready` bundle. The
`slo-rules-engine/approved-provider-plan/v1` document records:

- a content-addressed approved-plan ID
- explicit reviewer identity, timestamp, and notes
- source bundle ID and target identity
- bundle review content and fingerprint
- provider change-plan, manifest, manifest-review report, and reviewed-handoff
  artifact fingerprints
- the fully validated dry-run `ProviderStatePlan`
- the managed output directory derived from the plan's contained file paths

Approval currently accepts only `manifest_bundle` and `external_generator`
targets. Datadog `live_api` targets are rejected until a safe live backend
recheck contract is verified.

`plan apply` requires `--confirm` and `--journal-dir`. It locks the selected
managed scope, rebuilds the current dry-run plan only for an immediate
fingerprint comparison, and discards those regenerated operations. Matching
state executes operations reconstructed from the approved plan. Changed state
returns `stale_approved_plan`; same-scope concurrency returns
`approved_plan_scope_busy`. Both stop before provider operations.

The operation journal records the live execution-plan identity and a validated
approved-plan reference containing approved plan ID, dry-run provider-plan
fingerprint, source bundle ID, and evidence fingerprint. Post-write verification
still rereads every attempted engine-owned file. Sloth downstream generation
remains explicitly pending.

Approved output persistence is idempotent for identical content and rejects
conflicting content without overwrite. Reapplying a completed plan rechecks
managed state and returns the existing verified journal/result without
rewriting files. A partial or failed journal returns
`approved_plan_requires_resume`, preserves all attempts, and includes manual
state-recheck and rollback guidance. `plan resume` can then retry only
journal-eligible file writes after proving prior successes still converge; it
preserves attempt history and re-verifies every engine-owned file. Datadog
resume, non-resumable retries, and rollback execution remain future work.

## Multi-Target File-Backed Apply

`bundle apply` accepts one valid `apply_ready` bundle and exactly one approved
plan per target. Before any target begins, it verifies:

- every target uses `manifest_bundle` or `external_generator` automation
- the approval set covers every target exactly once with no unknown target
- every approval names the source bundle ID and exact target identity
- bundle-review, provider-plan, manifest, manifest-review, and handoff
  fingerprints still match the packaged artifacts
- the requested applied-bundle destination is absent or is the compatible
  immutable result of the same predecessor and approved-plan set

Datadog or mixed live/file bundles return
`unsupported_bundle_apply_target`. Coverage, evidence, source freshness, and
output conflicts also fail before a target journal or managed-file write.

Targets execute in deterministic UID order through `ExactPlanExecutor`. The
command stops after the first non-success target and reports its UID, journal,
and all earlier completed target results. It does not write an applied bundle
until every target returns `succeeded` or `noop`. A partial target must be
reviewed and explicitly resumed with `plan resume`; rerunning `bundle apply`
then replays already-converged targets without rewriting their files.

Successful execution creates a new content-addressed `applied` bundle with an
`apply` transition to the `apply_ready` predecessor. Each target references a
generated `execution_result` artifact whose
`slo-rules-engine/bundle-target-execution/v1` content includes the
approved-plan reference, approved managed runtime, full operation-journal
fingerprint and reference, and terminal `ProviderStateResult`. Execution counts
and statuses are included in aggregate and provider summaries. Identical replay
persists identical bundle bytes; conflicting output is never overwritten.

## Read-Only File-Backed Verification

`bundle verify` accepts one valid `applied` bundle. Before the first managed-file
read it rechecks:

- release-bundle schema, content identity, source freshness, `apply` lineage,
  target coverage, and execution-artifact fingerprints
- that every target uses `manifest_bundle` or `external_generator` automation
- each packaged approved-plan reference and dry-run provider-plan fingerprint
- each terminal journal's schema, content fingerprint, deterministic journal
  identity, provider/service identity, approved-plan reference, and result
  fingerprints
- exact journal-entry agreement with the packaged change plan and containment
  of every managed path under the approved service/provider runtime
- every supplied Sloth evidence/runtime mapping, current evidence schema and
  source derivation, exact target manifest/service/SLO coverage, and safe
  credential-free Prometheus-compatible base URL

The command then checks targets in stable UID order and journal entries in
recorded position order. `ManagedFileVerifier` parses each engine-owned JSON or
YAML file and compares a fresh presence/content fingerprint with desired state
from the approved operation. When a Sloth target has an explicit runtime, the
command also executes only the eight persisted evidence bindings through
read-only Prometheus instant queries. It never updates the journal, rewrites a
managed file, invokes Sloth, reloads configuration, or mutates any backend.

Success creates a new content-addressed `verified` bundle with a `verify`
transition to the immutable `applied` predecessor. Each target references one
generated `target_verification` artifact whose
`slo-rules-engine/bundle-target-verification/v1` content includes:

- target, approved-plan, runtime, provider-plan, and terminal journal identity
- one fresh expected/actual result for every engine-owned managed file
- aggregate `status`, `engine_owned_status`, and `external_status`
- pending Sloth external-generator requirements when no runtime is requested,
  or the packaged evidence identity and full neutral live-status report when
  downstream provider state is proven

A target qualifies when `engine_owned_status` is `succeeded`; its overall
verification may remain `pending` only for recorded external Sloth work. With
current evidence and an explicit runtime, `missing_telemetry` or `unverifiable`
SLO state returns `bundle_target_verification_failed`; `healthy`, `at_risk`,
and `exhausted` all prove readable generated state and set
`external_status: succeeded` without redefining operational health as
configuration convergence.
Missing, unreadable, or changed engine-owned files return
`bundle_target_verification_failed` and no verified successor is written.
Datadog or mixed live/file bundles return
`unsupported_bundle_verify_target` before journal or managed-file reads.
Invalid journal, lineage, runtime, plan, or execution evidence returns
`invalid_bundle_verification_inputs` before managed-file reads.

An existing compatible engine-only verified output is rechecked using its
original verification timestamp, so converged replay returns identical bundle
bytes. A later live downstream snapshot should use a new output path because
status values and sample timestamps are immutable evidence.
An incompatible output returns `release_bundle_output_conflict` before managed
state is inspected and is never overwritten.

## Status Safety

Status evaluation checks:

- bundle schema
- every embedded artifact fingerprint
- the content-addressed bundle ID
- every recorded file source path and current source fingerprint
- generated plan lineage through the content-addressed identity
- persisted incomplete or stale findings

Source deletion or source-content drift makes the effective lifecycle `stale`. Embedded-content or identity tampering makes it `invalid`. Neither state is eligible for future bundle apply behavior.

## Commands

Create a review-ready bundle:

```bash
bin/rules-ctl bundle create \
  --artifact-index ./artifact-index.json \
  --reviewer team/payments-sre \
  --reviewed-at 2026-07-26T09:30:00Z \
  --sloth-evidence checkout-api/sloth=./sloth-evidence.json \
  --output ./release-bundle.json
```

The repeatable `--sloth-evidence` option is optional. When supplied, creation
validates the evidence schema and content ID, rereads and reconstructs every
linked local source, and requires exact target manifest/service/SLO coverage
before packaging. Runtime endpoints remain external to the bundle.

Package a current dry-run provider plan:

```bash
bin/rules-ctl bundle create \
  --artifact-index ./artifact-index.json \
  --reviewer team/payments-sre \
  --reviewed-at 2026-07-26T09:30:00Z \
  --plan checkout-api/prometheus_stack=./prometheus-stack-plan.json \
  --output ./release-bundle.json
```

Generate plans from the packaged Prometheus Stack manifest and current managed-file state:

```bash
bin/rules-ctl bundle plan ./review-ready-bundle.json \
  --target-output checkout-api/prometheus_stack=./managed \
  --output ./apply-ready-bundle.json
```

For a live API target, make the runtime backend selection explicit while keeping credentials outside the bundle:

```bash
bin/rules-ctl bundle plan ./review-ready-bundle.json \
  --target-backend checkout-api/datadog=environment \
  --output ./apply-ready-bundle.json
```

Inspect schema, identity, embedded fingerprints, and current source freshness:

```bash
bin/rules-ctl bundle status ./release-bundle.json
```

Approve and execute one file-backed target:

```bash
bin/rules-ctl plan approve ./apply-ready-bundle.json \
  --target checkout-api/prometheus_stack \
  --reviewer team/payments-sre \
  --reviewed-at 2026-07-27T14:00:00Z \
  --output ./approved-plan.json

bin/rules-ctl plan status ./approved-plan.json

bin/rules-ctl plan apply ./approved-plan.json \
  --confirm \
  --journal-dir ./journals

bin/rules-ctl plan resume ./approved-plan.json \
  --confirm \
  --journal-dir ./journals
```

Apply every approved target in one file-only bundle:

```bash
bin/rules-ctl bundle apply ./apply-ready-bundle.json \
  --confirm \
  --approved-plan ./approved-prometheus-stack-plan.json \
  --approved-plan ./approved-sloth-plan.json \
  --journal-dir ./journals \
  --output ./applied-bundle.json
```

Verify the applied release against current engine-owned managed files:

```bash
bin/rules-ctl bundle verify ./applied-bundle.json \
  --output ./verified-bundle.json
```

After external Sloth generation, also package current evidence and verify its
live generated state without persisting the runtime URL:

```bash
bin/rules-ctl bundle verify ./applied-bundle.json \
  --sloth-evidence checkout-api/sloth=./sloth-evidence.json \
  --target-base-url checkout-api/sloth=http://localhost:9090 \
  --max-age-seconds 300 \
  --output ./verified-downstream-bundle.json
```

Creation, planning, bundle execution, and bundle verification are fail-closed. Stale, invalid,
incomplete, or wrong-lifecycle predecessors; missing or unknown target runtime
configuration; invalid dry-run plans; credential-like structured keys; invalid
bundle schemas; incomplete/mismatched approvals; unsupported live targets; and
incompatible successor outputs produce nonzero status. Planning, apply, and
verify also reject in-place output so every predecessor remains immutable.
