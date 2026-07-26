# Release Bundle Contract

The first-class release bundle is a self-contained, versioned JSON document that packages reviewed onboarding evidence and provider delivery artifacts without contacting a backend.

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

Local source paths, lifecycle state, findings, summaries, and the onboarding artifact-index fingerprint do not define bundle identity. Rebuilding from unchanged release content and review metadata produces the same ID.

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

Each artifact includes a stable UID, kind, content type, SHA-256 fingerprint, source path, and embedded content. Provider targets reference the packaged manifest, review report, and optional plan by UID.

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

## Status Safety

Status evaluation checks:

- bundle schema
- every embedded artifact fingerprint
- the content-addressed bundle ID
- every recorded source path and current source fingerprint
- persisted incomplete or stale findings

Source deletion or source-content drift makes the effective lifecycle `stale`. Embedded-content or identity tampering makes it `invalid`. Neither state is eligible for future bundle apply behavior.
