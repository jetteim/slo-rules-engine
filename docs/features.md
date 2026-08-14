# Feature Inventory

This file tracks the long-running feature baseline.

See [Evolution Plan](evolution-plan.md) for value streams, capability mapping, contribution streams, and delivery order.
See [Telemetry-First Adoption Map](adoption-map.md) for the value-oriented onboarding path and near-term adoption backlog.

## Keep

- Ruby service level definition DSL.
- SLI, SLI instance, SLO, objective, evaluation-window, success condition, and calculation-basis concepts.
- Validation of naming, required fields, uniqueness, SLO objective ranges, and metric binding completeness.
- Validation that SLO alert route keys and provider-specific route sources exist.
- Reality checks against historical telemetry and measured metric inventories.
- SLI/SLO candidate generation from measured telemetry with findings for rejected or incomplete signals.
- Generation of SLO rules, burn-rate alerts, telemetry-gap notifications, dashboards, and delivery integration route catalogs.
- Machine-readable findings for unsupported or implementation-coupled definitions.
- Golden-style tests for generated artifacts.

## Onboarding Capability: Generate SLIs And SLOs From Telemetry

For services with existing telemetry, the most important onboarding path is telemetry lookup first, then generated candidate review. The engine should let maintainers start with measured telemetry and produce a reviewable service definition draft before any provider artifact generation.

Explicit features:

- **Telemetry inventory ingestion:** accept measured telemetry inventory JSON as the starting input.
- **Telemetry discovery baseline:** discover active metrics by service or selector scope before candidate review.
- **Portfolio discovery:** discover telemetry for multiple services through `discover-telemetry --scope-file`, preserve one normalized evidence file per scope, and write an aggregate `index.json` for later review ranking.
- **Signal eligibility review:** reject unsupported, non-user-visible, or metric-less signals with machine-readable findings.
- **SLI/SLO candidate inference:** map eligible signals to SLI identifiers, SLO identifiers, objectives, success conditions, and calculation-basis recommendations.
- **Candidate confidence and explanation:** explain why a signal became a candidate and how strong the evidence is before review.
- **Draft definition generation:** emit a public-safe Ruby DSL draft with candidate SLIs, metric bindings, instances, and proposed SLOs.
- **Saved evidence packets:** preserve discovery findings, candidate reasoning, and accepted review notes for later validation and provider handoff.
- **Generated draft validation:** ensure emitted drafts can be loaded by the DSL and validated before provider generation.
- **Review handoff:** preserve findings and conservative review wording so generated SLOs remain proposals until a maintainer accepts them.
- **Provider handoff:** keep backend-specific generation downstream of accepted definitions; providers translate accepted intent and do not invent SLO policy.

## Reliability Model Report

`rules-ctl model-report` summarizes the neutral reliability model for service definitions. It includes reviewed handoff provenance when definitions were generated from accepted onboarding packets, and is intended for review before provider generation using synthetic examples in this repository.

## Manifest Review Queue

`rules-ctl manifest-review` checks generated or saved provider manifests before apply workflows. It accepts repeatable `--manifest` inputs for provider-level saved reports, reports missing, incomplete, stale, or provider-mismatched reviewed provenance, links findings back to handoff packet labels and files when `--handoff-dir` is provided, can persist the report with `--output`, validates saved report freshness with `--report`, records deterministic manifest and handoff fingerprints, and emits queue-level rollups for reviewed manifests, missing provenance, incomplete provenance, stale provenance, accepted candidates, rejected candidates, and review notes.

`rules-ctl generate --output-dir` also writes `manifest-review/<provider>.json` beside generated provider manifests so artifact reviewers have a durable queue report without rerunning review checks. Saved reports include their own report path for handoff tooling.
Confirmed `apply` and `prune` can use `--handoff-dir` to block mutation when manifest provenance is stale relative to the latest reviewed handoff packet, and `--review-report` to block live mutation when the saved manifest-review report no longer matches the current manifest or handoff fingerprints.

## Onboarding Artifact Index

`rules-ctl onboarding-artifact-index` builds a compact handoff index from a saved discovery `index.json` plus optional handoff, draft, and generated manifest directories. It records per-scope completeness, missing artifact paths, reviewed handoff status, provider manifest links, manifest-review report links, saved manifest-review report validity and freshness, next-action guidance for incomplete, stale, or blocked handoff bundles, and the freshness validation command reviewers can run before trusting saved provider artifacts. Because generated manifest-review reports are provider-level, report creation, freshness validation, and stale-report refresh commands use the full saved manifest set for that provider instead of only the current scope's manifest. Saved path arguments in those commands are shell-escaped so artifact directories containing spaces remain usable.

The repository includes a public-safe telemetry-first fixture and walkthrough under `examples/onboarding/telemetry-first` and `docs/telemetry-first-walkthrough.md`. The walkthrough smoke test exercises saved discovery evidence, handoff review, draft generation, provider-bound manifest generation, saved report freshness validation, artifact indexing, and the pre-mutation review gate without requiring live backend credentials.

## Backend Telemetry Lookup And Sanity Checks

Telemetry-derived SLO generation should work from either a checked-in telemetry inventory fixture or backend lookup output. Lookup adapters normalize provider evidence before it reaches candidate generation, so SLI/SLO review does not depend on backend-specific query syntax.

Explicit features:

- **Provider telemetry lookup:** query Datadog or Prometheus-compatible backends through injectable clients and emit normalized telemetry inventory.
- **Service-scoped discovery:** inventory active metrics by service or selector scope through `discover-telemetry` and reuse the same normalized evidence shape as explicit lookup.
- **Batch discovery reuse:** `discover-telemetry --scope-file` reuses the same provider discovery adapter one scope at a time and persists saved evidence packets without provider-specific postprocessing.
- **Online sanity checks:** report missing metrics, missing time series, missing histogram buckets, and calculation-basis sensitivity from file telemetry, saved lookup results, or explicit online lookup.
- **Calculation-basis evidence:** use observed request volume and estimated failed observations before alerting to recommend observations-based or time-slice-based SLOs.
- **Candidate reuse:** feed lookup or discovery output into the same `candidates` and `draft-definition` flow as file-based telemetry inventory.
- **No hidden policy:** lookup output is evidence for review, not automatic SLO acceptance.

## Provider State Management

Provider generation is read-only. Backend state changes belong to explicit apply workflows.

Explicit features:

- **State pipeline contract:** model backend management as sources, transforms, sinks, and findings.
- **Versioned provider-state values:** plan and import outputs expose immutable desired-state and observed-state snapshots, provider-neutral changes and findings, stable fingerprints, and a result boundary under `slo-rules-engine/provider-state/v1`.
- **Provider evidence preservation:** shared state values retain Datadog API payloads, backend IDs, match identity, and risk; Prometheus Stack managed resources and paths; and Sloth native input and handoff evidence.
- **Automation modes:** providers declare `live_api`, `manifest_bundle`, or `external_generator`.
- **Reviewed manifest input:** apply workflows accept a reviewed provider manifest directly instead of forcing regeneration in the same command.
- **Reviewed manifest diff:** diff workflows compare desired reviewed manifests to observed provider state and emit `create`, `update`, or `noop` operations with changed paths.
- **Change impact summary:** diff, apply, and prune plans emit operation counts and destructive-operation counts before mutation.
- **Provider-specific risk signaling:** Datadog plans flag monitor recreate, force-delete SLO prune, and managed dashboard/monitor prune operations with risk levels and reasons.
- **Identity-confidence signaling:** Datadog import and plan output preserve whether backend resources were matched by managed `source_ref` identity or by weaker name/title fallback evidence.
- **Ownership-safety enforcement:** live Datadog `update`, `recreate`, and low-confidence `prune` delete operations are blocked when backend ownership was matched only by weaker name/title or service-scope fallback evidence.
- **Apply planning:** dry-run apply emits planned create, update, write, or handoff operations.
- **Explicit live mutation:** live backend changes require a separate command, confirmation, and credentials when the provider needs them.
- **Datadog live API support:** Datadog can apply SLOs, monitors, telemetry-gap monitors, and dashboards through API calls.
- **Datadog durable execution:** confirmed Datadog apply/prune requires
  `--journal-dir`, persists atomic attempts and returned backend identifiers,
  stops after the first failure, and emits a linked `ProviderStateResult`.
- **Datadog post-mutation verification:** after confirmed mutation, Datadog
  state is refreshed once and each attempted resource is checked for canonical
  payload and provider identity convergence or confirmed delete absence.
  Request evidence contains only method/path, response fingerprints, and
  top-level response keys; API failures are sanitized before persistence.
- **Datadog dashboard catalog reconciliation:** dashboard discovery, import,
  apply verification, and prune ownership use the paginated custom-dashboard
  catalog plus full dashboard details. Managed dashboards do not need manual
  dashboard-list membership to be found.
- **Payload provenance:** Datadog apply operations preserve the source artifact path through managed `source_ref` tags and use that identity during import, diff, apply, and prune.
- **Managed tag contract:** Datadog apply-ready payloads require managed identity tags such as `managed_by`, `service`, and `source_ref`, while reconciliation ignores unmanaged backend tags so provider-owned semantics drive drift detection.
- **Provider field contract:** Datadog apply-ready payloads validate SLO timeframe/threshold consistency, burn-rate query and threshold consistency, and telemetry-gap no-data monitor semantics before live mutation.
- **Time-slice Datadog SLO baseline:** reviewed counter-ratio `time_slice` SLOs translate into Datadog `time_slice` payloads with explicit slice interval, comparator, threshold, and formula/query structure, and that payload shape participates in diff reconciliation.
- **Threshold-based time-slice Datadog SLO baseline:** reviewed `success_threshold` SLOs backed by provider query expressions translate into Datadog `time_slice` payloads with operator-aware comparators, numeric thresholds, merged selector scope, and diff reconciliation support.
- **Threshold inference for Datadog time-slice SLOs:** reviewed threshold-based distribution and gauge bindings can infer Datadog query expressions from metric type, selector scope, objective, and operator when explicit provider query text is absent.
- **Traffic-floor inference for Datadog time-slice SLOs:** reviewed threshold-based counter bindings can infer Datadog `sum:...as_count()` query expressions from metric name and selector scope when explicit provider query text is absent.
- **Selector-aware Datadog dashboard evidence:** generated Datadog dashboard timeseries queries merge reviewed selector scope into provider query expressions so dashboard evidence stays aligned with the reviewed SLI instance rather than drifting to backend-binding-only scope.
- **Dashboard payload contract:** generated Datadog dashboards validate the expected template variables (`service`, `sli`, `sli_instance`, `slo`) and the generated note/timeseries widget structure before live mutation.
- **Manifest-backed providers:** Prometheus-compatible bundles and Sloth specs
  use the same apply command but manage deterministic files and handoff plans
  rather than mutating live backends. Confirmed mutation requires
  `--journal-dir`, persists operation attempts, and emits a
  `ProviderStateResult` with post-operation expected/actual file-state
  fingerprints. Sloth apply verifies both the reviewed engine manifest and
  native Sloth `prometheus/v1` generator input files while leaving downstream
  generation explicitly pending.
- **Approved provider plans:** one Prometheus Stack or Sloth target from a valid
  `apply_ready` release bundle can be locked into a content-addressed,
  credential-free approval artifact with explicit reviewer metadata, bundle
  lineage, evidence fingerprints, exact provider plan, and managed runtime.
- **Exact file-backed execution:** approved-plan apply acquires a same-scope
  lock, rechecks managed-file state, rejects stale observation fingerprints,
  executes only stored `write`, `noop`, and `handoff` changes, and links the
  approved plan through the durable journal and `ProviderStateResult`.
- **Completed exact-plan replay:** a terminal successful journal is returned
  idempotently only after current managed state is rechecked as converged;
  partial or failed journals are blocked without adding attempts and include
  state-recheck and manual rollback guidance.
- **Explicit exact-plan resume:** after operator review and correction,
  `plan resume` proves previous successes still converge, retries only
  journal-eligible file writes, preserves all attempt history, and re-verifies
  every engine-owned file.
- **Multi-target file-backed bundle apply:** one approved plan per target is
  preflighted against the same apply-ready bundle, then Prometheus Stack and
  Sloth targets execute in stable UID order through the exact-plan executor.
  Success creates a new content-addressed applied bundle with per-target
  journal/result artifacts; partial targets require explicit resume.
- **Read-only file-backed bundle verification:** one valid `applied` bundle is
  preflighted against packaged execution, approved-plan, runtime, provider-plan,
  and full journal fingerprints before managed files are read. Prometheus Stack
  and Sloth engine-owned files are freshly compared with approved desired state
  in stable order without writes. Success creates a content-addressed
  `verified` successor with one
  `slo-rules-engine/bundle-target-verification/v1` artifact per target; Sloth
  downstream generator evidence remains explicitly pending.
- **Exact-plan provider boundary:** Datadog approval/execution,
  Datadog resume, non-resumable operation retry, automatic rollback execution,
  and live/file mixed-bundle apply or verification remain explicit future work.
- **External-generator import:** Sloth import reads the managed manifest and every expected native input and reports missing external-generator input files.
- **Reviewed Sloth downstream evidence:** `sloth-evidence capture` structurally
  maps current reviewed Sloth manifest/native-input fingerprints to saved
  generated Prometheus records, exact provider status queries, and downstream
  reviewer attestation in one content-addressed credential-free artifact.
- **Sloth evidence freshness:** `sloth-evidence status` validates artifact
  identity before rereading manifest, native input, and generated-rule sources;
  semantic drift returns stable stale findings and a nonzero exit without any
  backend call.
- **Future provider contract:** new providers must document generation, reality-check, telemetry lookup, and apply behavior before being considered production-grade.

## Sloth Provider Generation

`rules-ctl generate --provider sloth` emits Sloth `prometheus/v1` SLO specs from reviewed service definitions. The provider uses Prometheus-compatible query bindings and keeps OpenSLO as a future interchange/export path, not as a backend provider.

Confirmed `rules-ctl apply --provider sloth` requires `--confirm`, a reviewed
`--manifest`, `--output-dir`, and `--journal-dir`. It writes the reviewed engine
manifest plus native Sloth YAML input files under
`<dir>/<service>/sloth/generated/`. The durable journal records file outcomes
and verified engine-owned file fingerprints, then marks the external
`sloth generate` handoff as intentionally skipped and pending; the engine still
does not execute the Sloth CLI or mutate downstream Prometheus resources.

After external generation, `rules-ctl sloth-evidence capture` requires current
reviewed manifest/native-input parity, complete unambiguous generated-rule
coverage for every SLO, objective and allowed-budget agreement, one consistent
Sloth identity, explicit reviewer/timestamp attestation, and credential-free
sources. It preserves the reviewed native total-event query for observations
because characterized Sloth output has no dedicated observation record.
`sloth-evidence status` rechecks every canonical source fingerprint. These
commands make no provider call. Direct Sloth live status now consumes only a
fresh exact-manifest evidence artifact and an explicit Prometheus runtime;
downstream bundle verification remains separate.

The official Sloth main branch also contains a stateless read-only Streamable
HTTP MCP server. A planned version-gated provider adapter will first use its six
tools for supplemental discovery/status cross-checks reconciled by exact
`sloth_id`. It cannot replace the direct reader until observations, exact source
record identity, and sample freshness reach contract parity. This is distinct
from the engine-owned MCP server planned in AICLI-F6.

## Prometheus Stack Provider Generation

`rules-ctl generate --provider prometheus_stack` emits one base observation recording rule for every SLI instance and derived evaluation-window success-ratio, error-ratio, objective-ratio, error-budget-ratio, and error-budget-remaining-ratio recording rules for every reviewed SLO. Burn-rate recording rules remain SLO-specific and calculate each burn value over its own policy window. Record names are normalized to valid Prometheus metric identifiers while reviewed service, owner, SLI, instance, SLO, objective, evaluation window, and calculation-basis identity remains available as labels.

The provider also renders a native Prometheus Operator `PrometheusRule`, a
Grafana sidecar-compatible dashboard `ConfigMap`, and a credential-free
Alertmanager route-intent document. Confirmed file apply validates all three
resource shapes, requires `--journal-dir`, writes them beside the reviewed
provider manifest, and emits durable per-file outcomes with completed local
verification. `plan`, `diff`, `import`, and `prune` cover every file in that
managed bundle. The route-intent document deliberately requires downstream
receiver configuration; it does not invent an Alertmanager webhook host,
secret, or credential.

Selector-based SLOs calculate success ratios from scoped counter rates. Threshold-based SLOs generate boolean time-slice ratios and require a numeric threshold plus `time_slice` calculation basis; unsupported threshold intent is rejected during provider validation rather than emitted as a misleading success ratio.

## Live SLO And Error-Budget Status

`rules-ctl status` reads one reviewed `prometheus_stack` manifest, one reviewed
`sloth` manifest with fresh downstream evidence, one current reviewed release
bundle, or one explicit live-status portfolio. It queries only generated
recording-rule identifiers or evidence-declared Sloth bindings through the
Prometheus-compatible instant-query API. The provider-neutral
`slo-rules-engine/live-slo-status/v1` report normalizes objective attainment,
remaining/consumed budget, burn-rate windows, observation count, source age,
freshness, reviewed context, provider resource identifiers, query evidence, and
machine-readable findings. Bundle and portfolio modes wrap each unchanged
target report in `slo-rules-engine/live-slo-status-aggregate/v1` with
deterministic target and state rollups.

The reader distinguishes `healthy`, `at_risk`, `exhausted`,
`missing_telemetry`, and `unverifiable`. It treats those classifications as
operational report data rather than CLI failures. Unreviewed or invalid
manifests, stale bundles, invalid portfolios, and incomplete or unknown
per-target runtime mappings fail before backend access. Sloth direct reads also
reject invalid/stale evidence, manifest/service drift, or incomplete SLO
coverage before client construction. Mixed-provider aggregates retain Datadog
targets and Sloth targets without evidence as explicit unsupported coverage;
evidence-backed Sloth targets use the same neutral report and require explicit
runtime mappings. An input with no readable target fails. Runtime URLs and raw
backend error messages are not copied into reports. Datadog remains
evidence-gated.

`rules-ctl sloth-mcp compare` adds a provider-specific read-only cross-check for
the official Sloth main-branch MCP server. It requires current exact-manifest
downstream evidence, a runtime host allowlist, the tested protocol/version, the
pinned six-tool read-only inventory and schemas, bounded pagination/responses,
and exact `sloth_id` coverage. It saves
`slo-rules-engine/sloth-mcp-comparison/v1` with objective, period, burn, budget,
availability, identity, capability, and drift evidence but no endpoint or raw
provider text. The artifact explicitly is not an authoritative neutral status
transport because upstream lacks observations, exact record identity, and
equivalent sample freshness.

## Planned Agent-Operable Interfaces

The [Agent Interface Roadmap](agent-interface-roadmap.md) defines a planned
Phase 14 capability. Its AICLI-F1 foundation and AICLI-F2 runtime introspection
slice are implemented; structured Agent invocation and MCP remain planned.

Implemented foundation:

- **Validated command registry:** all 40 current command IDs declare Human and
  planned Agent mappings, contract references, side effects, local/provider
  I/O, credential categories, safety gates, output controls, and MCP
  eligibility. Missing or duplicate metadata fails closed.
- **Separate command catalog:**
  `slo-rules-engine/cli-command-catalog/v1` pairs each usual Human CLI example
  with a versioned planned Agent CLI JSON request.
- **Registry-backed Human dispatch:** top-level and grouped Human commands
  resolve through the registry while retaining existing handlers, stdout, exit
  codes, and refusal behavior.
- **Runtime introspection:** offline, bounded `agent catalog` and exact `agent
  describe` output expose request/result/error references, strict resolved
  request schemas, side effects, provider I/O, credential categories, safety
  gates, and output/MCP metadata without loading files or providers.

Planned features:

- **One command contract:** the implemented versioned registry covers every current command,
  request/result/error schema, side effect, provider read/write, safety gate,
  Human CLI mapping, Agent CLI mapping, skill reference, and later MCP tool.
- **Two feature-parity CLI sub-interfaces:** the existing Human CLI retains
  convenience flags and compatibility; a new Agent CLI accepts complete strict
  JSON requests. Both normalize into the same handlers and safety behavior.
- **Agent input hardening:** strict schemas and field-specific validation cover
  unknown fields, bounds, path traversal/symlink escape, control characters,
  unsafe IDs, embedded query/fragment syntax, pre-encoding, URLs, and
  credential exclusion.
- **Distinct safety modes:** zero-I/O `validate_only`, observational planning,
  and confirmed execution are explicit and retain every current review,
  ownership, exact-plan, confirmation, journal, and verification gate.
- **Context-safe output:** schema-checked field masks, limits/cursors, NDJSON,
  explicit truncation, stable error envelopes, and sanitization/quarantine for
  provider-controlled free text.
- **Agent distribution:** a versioned `SKILL.md`, compact context guidance,
  headless credential references, and a later allowlisted MCP stdio adapter all
  derive from the registry.
- **Parity as a release gate:** every CLI change updates both sub-interfaces,
  schemas, equivalence tests, runtime introspection, usage, and MCP projection
  when available; no one-interface-only command is accepted.

The raw structured path represents a full rules-engine command, not an
arbitrary provider API payload. Neutral reliability intent and reviewed
provider artifacts remain authoritative. Catalog Agent JSON examples and their
strict schemas are introspectable contracts; execution remains unavailable
until the next AICLI-F2 slice implements `agent invoke` and result envelopes.

## Change

- Provider abstraction means complete observability backend bundle.
- Backend-specific details move out of core DSL and into providers.
- Alert delivery goes through generated contextual routes.
- Public examples use generic services and public-safe domains.
- Configuration replaces hard-coded platform constants.

## Remove

- Organization-specific service names.
- Internal domains and CI references.
- Internal project metadata APIs.
- Platform-specific deployment writers.
- Secret formats tied to one organization.

## Preserve As Generalized Reliability Knowledge

- Error-budget burn-rate thresholds.
- Observation-based and time-slice-based SLO calculation.
- Missing metric and missing telemetry detection.
- Provider-specific capability validation.
- Dashboard links from alerts.
- Route availability checks before alert delivery.
