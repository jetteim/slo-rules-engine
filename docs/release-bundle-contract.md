# Release Bundle Contract

The first-class release bundle is a self-contained, versioned JSON document that packages reviewed onboarding evidence and provider delivery artifacts. Bundle creation and file-backed planning require no backend calls; live API planning reads current provider state but never mutates it.

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
- deterministic lifecycle-transition metadata when the bundle was derived by `bundle plan`
- generated-artifact lineage metadata

Local file source paths, lifecycle state, findings, summaries, and the onboarding artifact-index fingerprint do not define bundle identity. Rebuilding from unchanged release content, review metadata, and planning evidence produces the same ID.

## Lifecycle

Supported persisted lifecycle states:

- `incomplete`: a required predecessor artifact, review decision, or plan contract is missing or invalid
- `review_ready`: discovery, handoff, reviewed definition, provider manifest, and fresh manifest-review evidence are packaged
- `apply_ready`: every provider target also has a valid dry-run change plan
- `stale`: current review evidence no longer matches its predecessor artifacts
- `applied`: reserved for the future bundle apply transition
- `verified`: reserved for the future post-apply verification transition

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
- optional dry-run provider change plan

Each artifact includes a stable UID, kind, content type, SHA-256 fingerprint, source metadata, and embedded content. File-backed predecessors record an absolute source path. Bundle-native plans record generated lineage to the predecessor bundle and provider target instead of inventing a mutable source file. Provider targets reference the packaged manifest, review report, and optional plan by UID.

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

The command creates a new `apply_ready` bundle with a new content-addressed ID, a transition reference to its predecessor, one generated dry-run plan per target, and provider-level operation and risk summaries. It never edits the predecessor bundle.

File-backed providers require a per-target managed output directory. Planning reads that directory to distinguish `write` from `noop` but does not create, update, or delete files. Live API providers require the explicit `environment` backend mode; credentials stay in the environment and never enter the bundle. Their planning path may read current backend state but does not invoke provider mutations.

Provider summaries include target and plan counts, total and actionable operations, destructive operations, risky operations, highest risk, and counts by action, resource target, and risk level. Risk classification remains provider-owned.

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
  --output ./release-bundle.json
```

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

Creation and planning are fail-closed. Stale, invalid, incomplete, or wrong-lifecycle predecessors; missing or unknown target runtime configuration; invalid dry-run plans; credential-like structured keys; and invalid bundle schemas produce nonzero status and do not write the requested output file. Planning also rejects in-place output so the predecessor remains immutable.
