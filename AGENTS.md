# AGENTS.md

## Purpose

This repository is a public-safe SLO rules engine.

It models provider-independent reliability intent in a Ruby DSL, generates provider-specific observability artifacts, and is being deepened into an explicit provider-state management engine with `diff`, `import`, `apply`, and `prune`.

## Current Priority Order

1. Capture reviewed Sloth downstream generated-rule identity as explicit
   evidence before adding Sloth live status
2. Production-grade Datadog reconciliation only when isolated backend evidence
   is available
3. Sloth live status after the downstream identity evidence contract exists
4. Datadog exact-plan parity only after live recheck/idempotency semantics are
   verified

The release-bundle create/plan/apply boundary, provider-neutral state/journal
contracts, file-backed apply-exact-plan workflow, and one-manifest
Prometheus-compatible live-status boundary are implemented. Release-bundle and
portfolio live-status aggregation are also implemented with explicit
per-target runtime, source preflight, deterministic rollups, and retained
partial evidence. The atomic coherence-preserving simplification checkpoint is
complete with repository-wide traceability, current architecture
documentation, a thin executable/library CLI boundary, consolidated structural
tests, and shared public-safe manifest fixtures. Live Datadog sandbox testing
is explicitly postponed by the user. Phase 9 is now complete through a
read-only file-backed `bundle verify` transition.

Current release-bundle status: `slo-rules-engine/release-bundle/v1` packages
discovery evidence, reviewed handoffs and definitions, provider manifests,
fresh manifest-review reports, dry-run plans, and terminal file-target execution
evidence into a content-addressed JSON document. `bundle create` is fail-closed
for incomplete, stale, invalid, or credential-bearing input. `bundle plan`
rechecks predecessor freshness, requires explicit runtime configuration for
every target, leaves the predecessor immutable, performs no provider mutation,
and writes a new content-addressed `apply_ready` bundle. `bundle apply`
preflights one approved plan per file-backed target, rejects live/mixed bundles,
executes exact plans in deterministic UID order, and writes an immutable
`applied` successor only after every target succeeds or safely replays.
`bundle verify` preflights execution, approved-plan, runtime, provider-plan,
and full journal fingerprints before managed-file reads, then creates an
immutable `verified` successor only when every engine-owned file freshly
converges. Sloth downstream execution remains explicitly pending.
`bundle status` detects schema errors, embedded tampering, identity mismatch,
missing sources, and source drift.

Current state-manager status: confirmed Prometheus Stack and Sloth apply/prune
requires `--journal-dir`, persists atomic per-operation transitions and attempt
evidence, stops after the first file failure, and emits a linked
`ProviderStateResult`. Managed paths are recorded as resource identifiers.
Every attempted engine-owned file is refreshed after execution with
expected/actual state fingerprints and stable findings. Sloth keeps downstream
generation explicitly pending. Confirmed Datadog apply/prune now uses the same
durable journal/result boundary, records sanitized request outcomes and returned
backend identifiers, and refreshes backend state to verify canonical payload
and identity convergence or delete absence. Datadog dashboard reconciliation
now reads the paginated custom
dashboard catalog and full details instead of assuming manual dashboard-list
membership. A public-safe sandbox smoke command can validate credentials,
catalog/detail reads, and an explicitly confirmed temporary dashboard
create/find/delete cycle without storing credentials or raw backend bodies.

Current exact-plan status:
`slo-rules-engine/approved-provider-plan/v1` locks one Prometheus Stack or
Sloth target from a valid `apply_ready` bundle with reviewer attestation,
bundle lineage, evidence fingerprints, exact provider plan, and managed
runtime. `plan apply` serializes the managed scope, rejects changed observed
state, executes only stored operations, journals the approved-plan reference,
and verifies final files. Completed plans replay without mutation after a fresh
convergence check. `plan resume` retries only journal-eligible writes after
proving earlier successes still converge, preserves all attempts, and
re-verifies the full file set. Datadog exact apply/resume remains postponed
with live backend validation.

Current multi-target apply status: successful Prometheus Stack and Sloth bundle
execution records one generated
`slo-rules-engine/bundle-target-execution/v1` artifact per target with approved
plan, managed runtime, full journal fingerprint/reference, and
`ProviderStateResult`. Missing/duplicate/unknown
approval coverage, bundle/evidence mismatch, stale sources, unsupported live
targets, and incompatible output destinations fail before the first target.
Execution stops on the first incomplete target, preserves earlier target
results, and requires explicit `plan resume` before a rerun can finish the
applied transition. Completed targets replay without rewriting files.

Current multi-target verification status: `bundle verify` accepts one valid
file-backed `applied` bundle, validates all source, lineage, target, execution,
plan, runtime, result, and terminal-journal evidence before the first managed
file read, and checks targets/entries deterministically through the shared
`ManagedFileVerifier`. Success writes one generated
`slo-rules-engine/bundle-target-verification/v1` artifact per target in a new
content-addressed `verified` successor. Prometheus Stack converges fully;
Sloth engine-owned manifest/input files converge while external generator and
downstream Prometheus requirements stay pending. Drift writes no successor.
Datadog or mixed live/file bundles fail before journal or target reads.

Current live-status status: neutral SLO intent now includes an explicit
evaluation window with a `30d` compatibility default. Prometheus Stack
generation emits evaluation-window success/error ratios, allowed and remaining
error-budget records, and burn-rate records calculated over their own policy
windows. `status --provider=prometheus_stack --manifest=...` requires one
reviewed manifest and performs GET-only instant queries against generated
record names. The versioned report distinguishes `healthy`, `at_risk`,
`exhausted`, `missing_telemetry`, and `unverifiable`, preserves reviewed
identity/context and provider evidence, detects reviewed/provider objective
drift, sanitizes backend failures, and can save the same timestamped/freshness
report printed to stdout. `status --bundle=...` and `status --portfolio=...`
emit `slo-rules-engine/live-slo-status-aggregate/v1`, retain every readable
target report, expose unsupported Datadog/Sloth targets as coverage gaps, and
require one runtime endpoint per readable target without persisting those URLs.
Stale bundles, invalid portfolios, review gaps, target mismatches, and runtime
mapping errors fail before the first backend read. Datadog and Sloth readers
remain open and evidence-gated.

Current architecture status: `bin/rules-ctl` is a six-line bootstrap for
`lib/slo_rules_engine/cli.rb`. The library facade composes eight focused command
families and retains shared manifest/state orchestration. The current component,
flow, dependency, contract, NFR, use-case, and test maps live in
`docs/design.md` and
`docs/housekeeping/atomic-coherence-simplification.md`.

## Non-Negotiable Working Rules

- Keep the repo public-safe. Private/internal rules are reference material only and must not be copied in.
- Prefer the existing neutral DSL and provider contract over provider-specific policy.
- Commit and push often.
- Add verification evidence before claiming a checkpoint is complete.
- Update this file when a checkpoint materially changes current priorities, recent checkpoints, or the next recommended slice.
- Keep `README.md` and `docs/use-cases.md` current whenever command scope, provider output, workflow behavior, or safety boundaries change; rewrite usage around engineering tasks instead of appending to a stale command catalog.

## Current State Summary

Implemented and already pushed:

- Neutral Ruby DSL, model, validation, provider registry
- Datadog / Prometheus stack / Sloth generation
- Telemetry lookup, discovery baseline, candidates, draft-definition, reality checks
- Reviewed manifest flow
- `diff`, `import`, `apply`, `prune`
- Provider contract enforcement
- Manifest schema validation
- Datadog payload validation before live mutation
- Drift-aware Datadog apply (`noop` when state already matches)
- Drift-aware manifest-bundle apply (`noop` when file already matches)
- Datadog import findings for missing expected resources
- Datadog prune based on service-scoped managed orphan discovery
- Datadog import findings for orphan managed resources
- Datadog dashboard ownership tags and tag-based managed-state discovery
- Datadog source-tag reconciliation for `existing_state`, `import`, and `prune` when backend names drift
- Datadog managed-tag validation and unmanaged-tag canonicalization during reconciliation
- Datadog SLO and monitor field-contract validation before live mutation
- Datadog counter-ratio `time_slice` SLO translation, validation, and diff reconciliation
- Datadog threshold-based `time_slice` SLO translation for provider query expressions with reviewed `success_threshold`
- Datadog dashboard evidence queries now merge reviewed selector scope into provider query expressions
- Datadog threshold-based distribution and gauge `time_slice` SLOs can infer provider queries from reviewed metric bindings when explicit query text is absent
- Datadog threshold-based counter `time_slice` SLOs can infer traffic-floor queries from reviewed metric bindings when explicit query text is absent
- Datadog dashboard payloads now validate the generated template-variable and note/timeseries widget contract explicitly
- Datadog payload readers now prefer hash keys over colliding Ruby methods such as `Hash#default`
- `diff`, `apply`, and `prune` plans now emit shared change-impact summaries with total, actionable, destructive, action, and target counts
- Datadog state plans now flag recreate and prune-delete operations with provider-specific risk levels and reasons
- Datadog import and state plans now preserve `match_identity` evidence and flag weaker name/title fallback matches explicitly
- Live Datadog `update` and `recreate` mutations are now blocked when ownership was matched without managed `source_ref` identity
- Live Datadog prune deletes are now also blocked when ownership confidence is only service-scope fallback
- Datadog import and diff fallback matching now reject same-name SLOs and same-title dashboards unless they are explicitly engine-managed
- Datadog duplicate `source_ref` and duplicate fallback matches now degrade to low-confidence identity instead of being silently accepted as trustworthy
- Batch telemetry discovery via `discover-telemetry --scope-file` with one provider per run
- One saved normalized discovery evidence file per scope plus aggregate `index.json`
- CLI validation for scope-file conflicts, required output directory, and per-scope runtime failure recording
- `onboarding-summary <discovery-index.json>` ranks saved discovery scopes as `ready`, `partial`, `insufficient`, or `failed`
- `.forbidden-terms` has been removed from repo history and is now local-only and gitignored

Implemented by the latest feature slices:

- Prometheus Stack generation now emits one non-duplicated base observation recording rule per SLI instance
- Neutral SLO intent now carries a validated evaluation window with a `30d`
  compatibility default, and generated onboarding drafts expose it explicitly
- Each reviewed Prometheus SLO now has evaluation-window success-ratio,
  error-ratio, objective-ratio, allowed/remaining error-budget, and
  policy-window burn-rate recording rules
- Prometheus SLO recording-rule labels retain the reviewed evaluation window,
  and Grafana dashboards include remaining error budget
- The Prometheus Stack provider declares `live_slo_status`; Datadog keeps its
  currently verified `30d` timeframe boundary and rejects other neutral windows
  during provider validation
- `slo-rules-engine/live-slo-status/v1` normalizes objective attainment,
  remaining/consumed budget, burn rates, observations, timestamps, freshness,
  reviewed context, provider resources, evidence, and findings
- The live-status classifier distinguishes `healthy`, `at_risk`, `exhausted`,
  `missing_telemetry`, and `unverifiable` with deterministic precedence
- Provider-observed objective and budget values are checked against reviewed
  manifest intent; mismatch is `unverifiable`
- `status --provider=prometheus_stack --manifest=...` requires reviewed
  provenance, accepts a freshness limit, optionally saves the stdout report,
  and contacts only `/api/v1/query`
- Datadog live status is explicitly refused, and raw provider error messages
  are not copied into status evidence
- `status --bundle=...` validates current release-bundle sources before backend
  access and emits `slo-rules-engine/live-slo-status-aggregate/v1`
- `status --portfolio=...` resolves credential-free
  `slo-rules-engine/live-status-portfolio/v1` inputs relative to the portfolio
  file and validates every manifest, review, UID, and provider identity
- Aggregate status requires explicit `service/provider=URL` runtime mappings
  for every Prometheus Stack target, validates all mappings before constructing
  a client, and never persists runtime URLs
- Aggregate reports preserve complete target reports, deterministic target and
  five-state rollups, explicit unsupported Datadog/Sloth coverage, and one
  target's query failures as `unverifiable` without dropping successful targets
- Generated recording names satisfy the Prometheus metric-name contract
- Threshold-based Prometheus SLOs require numeric `time_slice` semantics and fail validation otherwise
- Prometheus Stack manifests now include a native Prometheus Operator `PrometheusRule`
- Prometheus Stack manifests now include a Grafana sidecar-compatible dashboard `ConfigMap`
- Alertmanager handoff now uses an explicit route-intent document that requires downstream receiver configuration and does not invent credentials
- Native Prometheus Stack resource shapes are validated before managed-file mutation
- Prometheus Stack `plan`, `apply`, `diff`, `import`, and `prune` now cover the reviewed manifest and every generated native file
- `docs/prometheus-stack-walkthrough.md` and `test/prometheus_stack_walkthrough_test.rb` prove the complete public-safe managed-file lifecycle
- Candidate review output includes confidence scores, reasons, caveats, and explanations for telemetry-derived drafts
- `onboarding-summary --handoff-dir` writes per-scope handoff packets preserving discovery evidence, candidate reasoning, and review state placeholders
- `review-handoff` records accepted and rejected candidate decisions in saved handoff packets while preserving discovery and candidate evidence
- `draft-from-handoff` emits reviewed Ruby DSL drafts from accepted handoff candidates without rerunning backend discovery
- `validate-handoff` checks reviewed packets before draft/provider handoff, and reviewed drafts include handoff provenance comments
- Reviewed handoff provenance is now parsed into the neutral DSL model and preserved in generated provider manifests
- Live `apply --confirm --manifest` now requires reviewed handoff provenance in every manifest before provider mutation or file-backed apply
- Rerun-safe onboarding summaries now preserve reviewed handoff decisions and expose review summaries plus reviewed provenance
- `model-report` now exposes reviewed handoff provenance from DSL definitions before provider generation
- `manifest-review` now checks generated or saved provider manifest queues for reviewed provenance gaps and emits review status rollups
- `generate --output-dir` now saves `manifest-review/<provider>.json` beside generated manifests
- `manifest-review --handoff-dir` now links findings back to handoff packet labels and files
- `manifest-review --output` now writes an explicit saved queue report
- `manifest-review --handoff-dir` now detects stale manifest provenance against reviewed handoff packets
- Saved manifest-review reports now include their own report path metadata
- Manifest-review reports now include deterministic manifest and handoff fingerprints for freshness checks
- Confirmed `apply --handoff-dir` and `prune --handoff-dir` now block stale handoff evidence before mutation
- `manifest-review --report` now validates a saved manifest-review report against current manifest and handoff fingerprints
- Confirmed `apply --review-report` and `prune --review-report` now block live mutation when the saved manifest-review report is stale
- Sloth external-generator handoff plans now include the manifest-review report path, freshness validation command, and stale freshness finding codes
- `onboarding-artifact-index` now ties saved discovery results, handoff packets, reviewed draft files, provider manifests, and manifest-review reports into one per-scope handoff index
- Onboarding artifact indexes now include per-scope next actions and aggregate next-action counts for incomplete saved handoff bundles
- Onboarding artifact indexes now surface saved manifest-review report validity, finding codes, and blocking next actions when reports exist but are not apply-ready
- Onboarding artifact indexes now validate saved manifest-review report freshness against current provider manifest and handoff artifacts, surface stale report finding codes, and point reviewers at the refresh command
- Onboarding artifact index freshness checks now compare provider-level saved manifest-review reports against all saved manifests for that provider, avoiding false stale reports in multi-scope handoff bundles
- `manifest-review` now accepts repeatable `--manifest` inputs, and artifact-index validation and refresh commands include every current manifest for the provider so multi-scope provider reports can be reproduced faithfully
- `docs/telemetry-first-walkthrough.md` and `test/telemetry_first_walkthrough_test.rb` now cover the saved-artifact flow through reviewed provider gates without live backend credentials
- `docs/housekeeping/test-suite-compaction-review.md` maps test-suite dependency shape and recommends compaction steps without changing test behavior
- `docs/housekeeping/abstraction-layer-review.md` maps abstraction layer pressure points and recommends extraction order without changing production code
- Sloth external-generator apply now writes native Sloth `prometheus/v1` YAML input files, includes them in plans/diffs/prune operations, and points handoff commands at those files while preserving the reviewed engine manifest as provenance
- Test support guardrails now include CLI helpers, onboarding handoff/discovery fixtures, and shared Datadog fake client/response fixtures
- Onboarding-related CLI commands now live in `lib/slo_rules_engine/cli/onboarding_commands.rb` instead of `bin/rules-ctl`
- Datadog apply coverage is split by behavior into applier state, payload translation, client state, and client HTTP suites while `test/datadog_apply_test.rb` remains the aggregate entrypoint
- Datadog provider risk signaling now lives in `SloRulesEngine::Datadog::RiskPolicy`
- Provider/integration catalog CLI commands now live in `lib/slo_rules_engine/cli/catalog_commands.rb`
- Datadog payload translation now lives in `SloRulesEngine::Datadog::PayloadTranslator`
- Telemetry CLI commands now live in `lib/slo_rules_engine/cli/telemetry_commands.rb`
- Datadog desired-state, diff, prune, and import-finding planning now lives in `SloRulesEngine::Datadog::StatePlanner`
- Datadog backend state discovery now lives in `SloRulesEngine::Datadog::StateReader`, leaving the client focused on credentials, HTTP retry/transport, deletes, and create-and-wait mutations
- Migration and model report CLI commands now live in `lib/slo_rules_engine/cli/report_commands.rb`
- Datadog request transport and retry behavior now lives in `SloRulesEngine::Datadog::RequestTransport`, leaving the client focused on credentials, state-reader delegation, deletes, and create-and-wait mutations
- `bundle plan` generates one dry-run provider plan per packaged target after rechecking predecessor schema, identity, artifact fingerprints, and file-source freshness
- File-backed bundle planning requires an explicit target output directory and reads managed state without writing files
- Live API bundle planning requires an explicit environment-backed runtime selection and keeps credentials outside the bundle
- Planning writes a new content-addressed `apply_ready` bundle with immutable predecessor lineage and generated plan-artifact lineage
- Bundle summaries now publish per-provider total, actionable, destructive, risky, action, resource-target, and risk-level counts
- Provider plans and imports now expose immutable `slo-rules-engine/provider-state/v1` desired-state, observed-state, change, finding, plan/import, and result value contracts
- Datadog shared state evidence preserves API payloads, backend IDs, match identity, and provider risk without weakening ownership gates
- Prometheus Stack shared state evidence preserves managed paths and native resource content
- Sloth import now reads native external-generator inputs and reports missing input files through the shared finding contract
- `journal create` verifies one saved dry-run provider plan and writes a
  deterministic `slo-rules-engine/provider-operation-journal/v1` document
- Operation journals bind provider, service, desired-state fingerprint,
  observed-state fingerprint, plan fingerprint, and ordered operation identity
- Journal entries preserve desired/observed payloads, changed paths, provider
  resource IDs, match identity, risk, resume classification, and verification
  requirements
- Initial actionable journal entries are `pending`, `noop` entries are
  `skipped`, and the schema supports `running`, `succeeded`, and `failed`
- Journal status assessment reports partial failure, state-recheck-required
  resume, and blocked resume for operations with uncertain side effects
- Datadog create/recreate/delete and Sloth handoff operations are conservatively
  non-resumable without manual verification; Datadog update and managed-file
  write require a fresh state check before retry
- Journal creation is atomic and idempotent for identical output, rejects
  conflicting existing output, and performs no provider mutation
- Engineering use cases now state exact stdout, saved-file, provider-read,
  provider-write, and refusal behavior for every supported workflow
- Confirmed Prometheus Stack and Sloth apply/prune now require durable journal
  storage before mutation
- File-backed journal transitions are serialized with exclusive locks and
  persisted through atomic replacement
- Journal entry transitions enforce `pending` to `running` to `succeeded` or
  `failed`, with unstarted operations allowed to become `skipped`
- Competing and terminal-state transitions, malformed attempt lifecycles,
  invalid timestamps, identity tampering, and credential-like keys are rejected
- Successful file operations record managed paths, byte/delete evidence, and
  timestamps; a failure records public-safe error evidence and skips later work
- File-backed apply/prune emits `ProviderStateResult` with `succeeded`,
  `partial`, `failed`, or `noop` status linked to live plan identity
- Sloth records the external-generator handoff as intentionally skipped rather
  than claiming downstream execution
- Repeated converged file-backed apply reuses an identical all-noop journal;
  journals containing execution evidence are never overwritten
- File-backed apply/prune refreshes every attempted engine-owned JSON/YAML path
  and records expected/actual presence and canonical content fingerprints
- Managed-file verification records terminal timestamps and stable findings for
  missing, unreadable, unexpectedly present, or mismatched paths
- A verification mismatch adds `post_apply_verification_failed`, fails an
  otherwise successful provider result, and makes the CLI exit nonzero
- All-noop results report verification `not_required` because the live plan
  already observed convergence immediately before execution
- Sloth reports verified engine-owned manifest/input state separately from its
  still-pending downstream generator and Prometheus state
- Confirmed Datadog apply/prune requires durable journal storage before
  mutation and persists atomic attempt transitions
- Successful Datadog attempts record request method/path, returned or existing
  provider resource IDs, response fingerprints, and response top-level keys
  without persisting raw API responses
- Datadog API failures are reduced to public-safe error evidence before journal
  persistence, and later operations are skipped after the first failure
- Datadog apply refreshes backend state once after mutation and verifies
  canonical payload plus provider identity for each attempted resource
- Datadog prune refreshes the managed service scope once and verifies each
  recorded resource ID is absent
- Missing, identity-mismatched, payload-drifted, surviving-delete, and
  refresh-failed resources emit stable verification finding codes and fail the
  linked `ProviderStateResult`
- Confirmed Datadog CLI apply/prune now requires `--journal-dir` after review
  evidence passes and before credentials or provider mutation
- Datadog dashboard discovery, import, convergence verification, and prune
  ownership now use the paginated custom-dashboard catalog plus full detail
  reads and do not depend on manual dashboard-list membership
- `scripts/datadog-sandbox-smoke` now provides a read-only credential/catalog
  probe and an explicitly confirmed temporary-dashboard create/find/delete
  probe with public-safe versioned output and cleanup attempts
- `docs/datadog-sandbox-testing.md` documents public trial and partner-sandbox
  paths, least-privilege scopes, regional sites, exact provider reads/writes,
  expected output, telemetry-discovery behavior, and credential revocation
- `plan approve` persists one immutable, content-addressed, credential-free
  Prometheus Stack or Sloth target with explicit reviewer metadata and locked
  bundle/manifest/review/handoff/provider-state fingerprints
- `plan status` revalidates approved-plan identity, provider-state
  fingerprints, evidence references, and managed path containment without
  contacting a backend
- `plan apply` acquires a nonblocking managed-scope lock, rejects stale
  immediate state, and reconstructs execution only from approved `write`,
  `noop`, and `handoff` changes
- Exact execution journals validate both live execution-plan identity and the
  approved dry-run plan ID/fingerprint; final managed files are re-read through
  the existing `ProviderStateResult` verification contract
- Completed exact plans replay idempotently only after a fresh convergence
  check and return the original journal/result without rewriting files
- Partial or failed exact plans return `approved_plan_requires_resume` without
  adding attempts and include manual state-recheck/rollback guidance
- `plan resume` proves all prior successes still converge, retries only
  journal-eligible file writes, preserves attempt history, and re-verifies
  every engine-owned file
- Same-scope concurrent exact apply/resume returns
  `approved_plan_scope_busy`; missing, stale, invalid, or non-resumable
  evidence fails before a new provider operation
- Datadog exact approval/apply/resume is intentionally rejected until safe live
  backend recheck/idempotency evidence is available
- `bundle apply` requires exact approved-plan coverage for every file-backed
  target and validates bundle, target, review, manifest, review-report, handoff,
  provider-plan, and output-destination identity before execution
- File-backed bundle targets execute in deterministic UID order through
  `ExactPlanExecutor`; live API or mixed bundles fail before any target starts
- Successful bundle execution writes a new content-addressed `applied` successor
  with one terminal `execution_result` artifact and provider rollup per target
- Incomplete target execution stops the sequence, reports earlier completions,
  writes no applied bundle, and advances only after explicit target
  `plan resume`; completed target replay is file-write-free
- Sloth resume now leaves a downstream handoff skipped after a repaired prior
  write failure instead of misclassifying the handoff as a retryable write
- The atomic repository-wide simplification checkpoint is complete with
  before/after structural evidence, all-use-case and all-contract traceability,
  a thin executable/library CLI boundary, consolidated structural coverage, and
  full behavioral verification
- `bundle verify` now closes the file-backed release lifecycle with immutable
  per-target verification artifacts, fresh expected/actual managed-file
  fingerprints, fail-closed evidence preflight, and explicit pending Sloth
  external state
- Applied target execution artifacts now preserve approved runtime and a full
  terminal journal fingerprint so later verification does not trust a mutable
  path alone

## Most Recent Checkpoints

- latest checkpoint: read-only file-backed bundle verification and immutable
  verified release evidence
- previous checkpoint: atomic coherence-preserving simplification with
  repository-wide traceability and current architecture
- previous checkpoint: release-bundle and portfolio live SLO/error-budget status
  aggregation with source/runtime preflight and retained partial evidence
- previous checkpoint: provider-neutral one-manifest live SLO/error-budget
  status with window-correct Prometheus recording rules
- previous checkpoint: fail-closed multi-target file-backed bundle apply with
  immutable applied-bundle evidence
- previous checkpoint: explicit state-checked resume for journal-eligible exact
  file writes with full re-verification
- previous checkpoint: converged completed-plan replay without file mutation
- previous checkpoint: immutable approved plans and exact Prometheus
  Stack/Sloth execution with stale-state and scope-concurrency rejection
- previous checkpoint: public-safe Datadog sandbox setup and read/mutation
  contract smoke workflow
- previous checkpoint: custom-dashboard catalog reconciliation independent of
  manual dashboard-list membership
- previous checkpoint: journal-backed Datadog execution outcomes and
  post-mutation backend convergence evidence
- previous checkpoint: post-operation Prometheus Stack and Sloth managed-file
  convergence evidence
- previous checkpoint: journal-backed Prometheus Stack and Sloth execution
  outcomes with partial-failure capture
- previous checkpoint: deterministic provider operation journals and
  intent/output-checked engineering use cases
- previous checkpoint: provider-neutral state value contracts across Datadog, Prometheus Stack, and Sloth
- previous checkpoint: immutable bundle-native provider planning and provider-level impact/risk summaries
- previous checkpoint: fail-closed `bundle create` and source-aware `bundle status`
- previous checkpoint: versioned content-addressed release-bundle contract
- previous checkpoint: public-safe reviewed Prometheus Stack bundle walkthrough
- previous checkpoint: managed PrometheusRule, Grafana dashboard, and Alertmanager route-intent file lifecycle
- previous checkpoint: complete Prometheus SLI and SLO recording-rule coverage
- previous checkpoint: reproducible provider-level manifest-review validation and refresh commands for multi-scope bundles
- previous checkpoint: onboarding artifact index provider-level saved report freshness for multi-scope bundles
- previous checkpoint: onboarding artifact index saved report freshness/staleness guidance
- previous checkpoint: onboarding artifact index saved report validity and blocking next-action guidance
- previous checkpoint: onboarding artifact index next-action guidance for incomplete saved handoff bundles
- previous checkpoint: Datadog request transport extraction and housekeeping pause decision
- previous checkpoint: Datadog state planner extraction, Datadog state reader split, and report CLI command extraction
- previous checkpoint: Datadog payload translator extraction and telemetry CLI command extraction
- previous checkpoint: Datadog coverage split, Datadog risk policy extraction, and catalog CLI command extraction
- previous checkpoint: CLI/onboarding/Datadog test guardrails plus onboarding CLI command extraction
- previous checkpoint: Sloth native external-generator input files for provider breadth
- previous checkpoint: housekeeping review recommendations for test compaction and abstraction layering
- previous checkpoint: telemetry-first saved-artifact walkthrough smoke test
- previous checkpoint: compact onboarding artifact index
- previous checkpoint: saved manifest-review freshness validation and artifact handoff freshness pointers
- previous checkpoint: handoff-aware live mutation gates and report freshness metadata
- previous checkpoint: stale provenance detection in manifest review reports
- previous checkpoint: saved manifest-review reports and handoff navigation
- previous checkpoint: provenance-aware manifest review queue checks
- previous checkpoint: reviewed provenance visibility in onboarding and model reports
- previous checkpoint: manifest review-evidence gate before live apply
- previous checkpoint: `feat: add onboarding handoff packets`
- previous pushed: `feat: add onboarding summary readiness ranking`
- earlier pushed: `chore: untrack forbidden terms list`
- `docs: finalize telemetry batch discovery handoff`
- `25c0de9` `feat: add telemetry batch discovery runner`
- `c9fbef8` `docs: add telemetry batch discovery plan`
- `e342fa5` `docs: add telemetry batch discovery design`
- `a28d6cf` `docs: clarify notification router integration role`
- `4a5260b` `fix: detect ambiguous datadog identity matches`
- `bfd78f5` `fix: require managed tags for datadog fallback matches`
- `70b5071` `feat: add datadog identity confidence signaling`
- `107a067` `feat: add datadog provider risk signaling`
- `ad18132` `feat: add provider state impact summaries`
- `88576ec` `docs: replace migration roadmap with adoption map`
- `4630f3e` `feat: report orphan datadog backend resources on import`
- `20b5d23` `feat: prune orphan datadog managed resources`
- `adf5f9b` `fix: skip noop manifest bundle apply operations`
- `b65acb2` `feat: report missing datadog backend resources on import`
- `67ecfd3` `fix: skip noop datadog apply operations`
- `a609161` `feat: validate datadog live apply payloads`

## Current Open Gaps

Highest-value remaining gaps:

1. Capture reviewed Sloth downstream generated recording-rule identity in a
   credential-free, source-linked evidence artifact
2. Add Sloth live status only after that identity evidence is complete
3. Run the Datadog sandbox probes and resume live provider-contract work only
   when the user makes credentials/evidence available
4. Extend exact approval/apply/resume to Datadog only after verified backend
   recheck and idempotency semantics exist
5. Add automatic rollback execution only after a reviewed compensating-plan
   contract exists; current exact failures provide manual guidance

Secondary gaps:

1. Broader state-management parity for future providers after Datadog and Prometheus Stack prove the shared contract
2. Automatic rollback execution only after a reviewed compensating-plan
   contract exists; current exact failures provide manual guidance
3. Further structural work only when a feature exposes a focused,
   behavior-tested responsibility

## Recommended Next Slice

Next recommended slice:

- define a versioned, credential-free Sloth downstream-evidence artifact that
  links one reviewed Sloth manifest/native input fingerprint to saved
  Sloth-generated Prometheus rule content
- parse generated rule YAML structurally and capture the exact recording-rule
  identities needed for objective attainment, remaining error budget, burn
  rate, observations, and freshness without running Sloth or reading a backend
- require explicit reviewer identity/timestamp and complete reviewed SLO
  coverage; reject stale source/input fingerprints, ambiguous rule mappings,
  credentials, and unrelated generated rules
- keep evidence capture read-only and provider-specific; do not move generated
  PromQL identities into the neutral DSL
- update usage with the precise stdout/file output, source reads, zero-write
  provider boundary, and refusal behavior

Rationale:

- Phase 9 now closes at a verified file-backed release without claiming Sloth
  downstream execution
- Sloth live status remains blocked specifically on reviewed generated-rule
  identity, so capturing that evidence is the smallest complete capability
  that removes a real product blocker
- saved generated rules can be validated locally without backend credentials,
  provider writes, or hidden metric/query translation
- Datadog work remains correctly evidence-gated and postponed

## Next Session Handoff

Prepared on 2026-07-29 for a restart-and-`proceed` workflow.

Current safe boundary:

- branch: `main`
- latest verified checkpoint: `feat: verify applied file release bundles`
  at the next `git log -1` entry
- previous verified checkpoint: `01f4e6d chore: complete atomic coherence
  simplification`
- expected startup state: `git status --short --branch` should show clean
  `main...origin/main`
- last full verification before handoff: `./scripts/verify.sh` exited 0 with `verification ok`

Verification evidence:

- target: read-only file-backed `applied` to `verified` release transition
- command: `./scripts/verify.sh`
- recorded timestamp: `2026-07-29T13:27:39Z`
- output path: agent terminal transcript; no separate repository artifact persisted
- result: exit 0, `verification ok`, 432 tests, 2,833 assertions, 0 failures, 0 errors
- metric/log/trace names: none; verification used local files and fake backend clients only
- live verification: not required; the feature reads local managed JSON/YAML
  and durable journals only. Datadog live testing remains postponed.
- blast radius: release-bundle execution/verification artifact schema,
  terminal journal references, file-backed bundle CLI lifecycle, summary
  rollups, and usage/contract documentation. Provider generation, neutral
  intent, live backend reads, and provider mutation behavior are unchanged.
- rollback path: revert the single `feat: verify applied file release bundles`
  commit

When the user types `proceed` in a fresh session:

1. First read this file, `docs/implementation-plan.md`, `docs/adoption-map.md`, and the latest 5-10 commits.
2. Confirm the worktree is clean with `git status --short --branch`.
3. Do not resume housekeeping; the atomic checkpoint and Phase 9 are complete.
4. Use TDD to define the reviewed Sloth downstream generated-rule evidence
   contract described above.
5. Keep evidence capture local and read-only; do not execute Sloth or contact
   Prometheus.
6. Keep Datadog live testing postponed unless the user explicitly reopens it
   with isolated credentials/evidence.
7. Preserve release-bundle predecessor immutability, exact-plan, review,
   journal, live-status, and mutation gates exactly.

## Verification Commands

Use these before claiming a checkpoint:

```bash
ruby -Ilib test/prometheus_stack_provider_test.rb
ruby -Ilib test/prometheus_stack_walkthrough_test.rb
ruby -Ilib test/cli_architecture_test.rb
ruby -Ilib test/live_status_test.rb
ruby -Ilib test/live_status_aggregate_test.rb
ruby -Ilib test/live_status_cli_test.rb
ruby -Ilib test/release_bundle_test.rb
ruby -Ilib test/release_bundle_cli_test.rb
ruby -Ilib test/release_bundle_apply_test.rb
ruby -Ilib test/release_bundle_apply_cli_test.rb
ruby -Ilib test/release_bundle_verify_test.rb
ruby -Ilib test/release_bundle_verify_cli_test.rb
ruby -Ilib test/provider_state_contract_test.rb
ruby -Ilib test/provider_state_journal_test.rb
ruby -Ilib test/provider_state_journal_cli_test.rb
ruby -Ilib test/provider_state_journal_transition_test.rb
ruby -Ilib test/manifest_bundle_execution_journal_test.rb
ruby -Ilib test/manifest_bundle_execution_cli_test.rb
ruby -Ilib test/use_cases_documentation_test.rb
ruby -Ilib test/onboarding_summary_test.rb
ruby -Ilib test/onboarding_handoff_test.rb
ruby -Ilib test/onboarding_artifact_index_test.rb
ruby -Ilib test/telemetry_first_walkthrough_test.rb
ruby -Ilib test/manifest_review_queue_test.rb
ruby -Ilib test/apply_test.rb
ruby -Ilib test/rules_ctl_test.rb
ruby -Ilib test/datadog_apply_test.rb
ruby -Ilib test/cli_test.rb
ruby -Ilib test/all_test.rb
ruby -Ilib test/forbidden_terms_test.rb
./scripts/verify.sh
git status --short --branch
```

## Resume Checklist

If a new session needs to resume quickly:

1. Read this file
2. Read `docs/implementation-plan.md`
3. Read `docs/adoption-map.md`
4. Read the latest 5-10 commits on `main`
5. Read the Sloth provider/status sections in `docs/features.md`,
   `docs/use-cases.md`, and `docs/live-status-contract.md`
6. Inspect Sloth manifests, native input generation, and current
   Prometheus-compatible status identity requirements
7. If the user says `proceed`, implement the reviewed Sloth downstream-evidence
   slice described above with TDD and source-first safety
8. Keep Datadog live testing postponed and preserve every exact-plan, review,
   journal, live-status, and mutation gate
