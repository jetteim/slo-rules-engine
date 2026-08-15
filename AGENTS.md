# AGENTS.md

## Purpose

This repository is a public-safe SLO rules engine.

It models provider-independent reliability intent in a Ruby DSL, generates provider-specific observability artifacts, and is being deepened into an explicit provider-state management engine with `diff`, `import`, `apply`, and `prune`.

## Current Priority Order

1. Extend AICLI-F3 from the validated read boundary into confined output paths
   and zero-I/O `validate_only` for the first local-write command family before
   expanding Agent mutation reach
2. Continue STR-1 through STR-7 only through their named preservation and
   dependency-removal gates
3. Production-grade Datadog reconciliation only when isolated backend evidence
   is available
4. Datadog exact-plan parity only after live recheck/idempotency semantics are
   verified
5. Revalidate the Sloth MCP comparison against a tagged binary only after an
   official release contains the upstream MCP server

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
converges. Sloth downstream execution remains explicit and pending by default;
an opt-in evidence/runtime mapping can additionally prove complete reviewed
generated state through GET-only Prometheus-compatible reads without executing
Sloth or mutating provider state.
`bundle status` detects schema errors, embedded tampering, identity mismatch,
missing sources, and source drift.

Current architecture-fitness status: STR-0 is complete without production-code
changes. `scripts/structure-report` deterministically inventories the current
94 production/executable files, 64 root requires, 40 registered commands, 11
command modules, 21 unique literal artifact schema IDs, all 120 per-command
schema references, 19 engineering use cases, and
the current hotspot set. `config/architecture_dependencies.json` assigns every
production file to exactly one boundary and allowlists every current forbidden
constant reference with its STR removal packet. New or changed forbidden edges,
unowned files, registry/catalog contract changes, schema inventory changes, or
missing use-case test mappings fail `scripts/structure-report --check` and the
aggregate suite. CLI command-module ownership is derived from the filesystem
and command registry rather than a hand-maintained command list.

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
downstream Prometheus requirements stay pending unless the caller supplies
current exact evidence and a runtime. Evidence-backed downstream verification
succeeds for complete readable `healthy`, `at_risk`, or `exhausted` reports and
fails without a successor for `missing_telemetry` or `unverifiable`. Drift
writes no successor.
Datadog or mixed live/file bundles fail before journal or target reads.

Current live-status status: neutral SLO intent now includes an explicit
evaluation window with a `30d` compatibility default. Prometheus Stack
generation emits evaluation-window success/error ratios, allowed and remaining
error-budget records, and burn-rate records calculated over their own policy
windows. `status --provider=prometheus_stack --manifest=...` requires one
reviewed manifest and performs GET-only instant queries against generated
record names. `status --provider=sloth --manifest=... --evidence=...` with an
explicit `--base-url=...` additionally requires fresh reviewed downstream
evidence for the exact manifest and queries only persisted provider bindings.
The versioned report distinguishes `healthy`, `at_risk`,
`exhausted`, `missing_telemetry`, and `unverifiable`, preserves reviewed
identity/context and provider evidence, detects reviewed/provider objective
drift, sanitizes backend failures, and can save the same timestamped/freshness
report printed to stdout. `status --bundle=...` and `status --portfolio=...`
emit `slo-rules-engine/live-slo-status-aggregate/v1`, retain every readable
target report, expose unsupported Datadog and Sloth-without-evidence targets as
coverage gaps, and require one runtime endpoint per readable target without
persisting those URLs.
Stale bundles, invalid portfolios, review gaps, target mismatches, and runtime
mapping errors fail before the first backend read. Datadog direct status remains
open. The official Sloth MCP adapter is implemented as comparison-only provider
evidence and cannot promote neutral status.

Current Sloth downstream-evidence status:
`sloth-evidence capture` reads one reviewed Sloth manifest, every native input,
and saved Sloth-generated Prometheus rule YAML. It requires exact canonical
manifest/input parity, complete and unambiguous generated-record coverage,
one consistent Sloth identity per reviewed SLO, objective/budget agreement,
explicit reviewer/timestamp attestation, safe YAML, and credential-free
sources. Success prints and saves one content-addressed
`slo-rules-engine/sloth-downstream-evidence/v1` artifact containing exact
record selectors plus the reviewed native observation query. `sloth-evidence
status` validates schema and content identity before rereading any source path,
then emits `slo-rules-engine/sloth-downstream-evidence-status/v1` with fresh or
stale canonical fingerprints. Both commands make zero provider calls and do
not run Sloth. Status also reconstructs saved mappings from current sources so
a rehashed altered artifact cannot become trusted provider input. Direct Sloth
live status, release/portfolio aggregation, and opt-in release-bundle
downstream verification consume this evidence. `bundle create
--sloth-evidence=TARGET=FILE` packages it by target, portfolio entries may
reference it, and `bundle verify` accepts explicit target evidence/runtime
mappings without persisting runtime URLs. `sloth-mcp compare` now preflights the
same exact reviewed evidence and consumes the official Sloth main-branch HTTP
MCP server through a version/tool/schema-gated six-tool read-only allowlist. It
emits a bounded content-addressed comparison report without endpoints or raw
provider text. Because upstream omits observations, exact record identity, and
equivalent freshness, the report declares itself non-authoritative and cannot
replace neutral status or the later engine MCP interface.

Current architecture status: `bin/rules-ctl` is a six-line bootstrap for
`lib/slo_rules_engine/cli.rb`. The library facade composes eleven focused command
families, dispatches through the versioned command registry, and retains shared
manifest/state orchestration. The current component, flow, dependency,
contract, NFR, use-case, and test maps live in
`docs/design.md` and
`docs/housekeeping/atomic-coherence-simplification.md`. The current measured
dependency debt, hotspot evidence, target direction, and eight execution
packets live in
`docs/housekeeping/project-structure-refactoring-plan.md`.

Current agent-interface status: AICLI-F1, AICLI-F2 runtime introspection, and
two executable AICLI-F2 vertical slices are implemented. A validated
immutable registry covers all 40 current commands and drives Human top-level
and grouped subcommand dispatch. The separate
`slo-rules-engine/cli-command-catalog/v1` entity pairs each executable Human CLI
example with a versioned Agent JSON request. Bounded offline `agent catalog`
and exact `agent describe` expose strict resolved request schemas and complete
side-effect/I/O/safety metadata with JSON-only errors. Strict inline JSON,
workspace-file, and stdin invocation now shares typed application commands with
the Human CLI for `providers.list`, `integrations.list`,
`recommend-calculation-basis`, `validate`, `migration-report`, `model-report`,
and file-backed `diff`. Agent reads are workspace-confined and bounded, reject
traversal/control/pre-encoding/symlink escape, retain Human result/exit parity,
and quarantine application stdout/stderr. Agent `diff` is limited to local
Prometheus Stack/Sloth managed-state reads with no provider network or writes.
Malformed, ambiguous, unsafe, unknown, unsupported, or gated requests return
JSON-only errors before disallowed I/O. Missing/duplicate metadata fails closed,
and current Human behavior remains characterized. Remaining command invocation,
output/URL/identifier hardening, validation-only write gates,
bounded/sanitized output, versioned skill, and MCP adapter remain planned.

## Non-Negotiable Working Rules

- Keep the repo public-safe. Private/internal rules are reference material only and must not be copied in.
- Prefer the existing neutral DSL and provider contract over provider-specific policy.
- Commit and push often.
- Add verification evidence before claiming a checkpoint is complete.
- Update this file when a checkpoint materially changes current priorities, recent checkpoints, or the next recommended slice.
- Keep `README.md` and `docs/use-cases.md` current whenever command scope, provider output, workflow behavior, or safety boundaries change; rewrite usage around engineering tasks instead of appending to a stale command catalog.
- Every CLI change must update both the Human CLI and Agent CLI sub-interfaces,
  their shared registry/schema metadata, equivalence tests, runtime
  introspection, and usage in the same checkpoint. For commands not yet enabled
  through structured invocation, update the target mapping and parity
  inventory; once MCP ships, update its generated projection as well.

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

- Release bundles can package one optional exact current Sloth downstream
  evidence artifact per target, and portfolio targets can reference the same
  evidence contract
- Release/portfolio aggregate status validates all evidence, source,
  manifest/service/SLO, and runtime mappings before constructing a client and
  reads evidence-backed Sloth targets through the shared reader
- `bundle verify` can opt into GET-only downstream Sloth state verification;
  it persists the full neutral report and evidence identity, never a runtime
  URL, and writes no successor for missing or unverifiable telemetry
- Human `bundle create` and `bundle verify` usage, planned Agent JSON mappings,
  registry metadata, README, use cases, and contracts cover the evidence/runtime
  inputs and exact output/refusal behavior
- Direct `status --provider=sloth` consumes fresh exact-manifest reviewed
  downstream evidence and an explicit Prometheus runtime
- Sloth live status emits the existing neutral five-state report with complete
  reviewed identity/context, objective, budget, burn, freshness, provider
  resource, and query evidence
- Sloth status preflight validates evidence schema/content ID, reconstructs
  mappings from current manifest/native/generated sources, checks source
  fingerprints, exact manifest/service identity, and complete SLO coverage
  before constructing the backend client
- Sloth manifests retain `sli_instance` for complete neutral status identity,
  and the provider now declares `live_slo_status`
- Human CLI usage, planned Agent JSON mapping, registry metadata, README, use
  cases, provider/status contracts, features, design, and roadmap include the
  Sloth status form
- `docs/sloth-mcp-integration.md` records the official Sloth main-branch
  Streamable HTTP MCP surface, six read-only tools, release/version status,
  setup, implemented comparison output, security/refusal rules, and parity gaps
- `sloth-mcp compare` requires current exact-manifest downstream evidence before
  client construction, then pins protocol `2025-11-25`, runtime version, server
  identity, exact six-tool inventory, read-only annotations, and input/output
  schema shapes before domain reads
- Sloth MCP comparison bounds endpoint hosts, time ranges, pagination, series
  points, response bytes, and deadlines; it reconciles exact `sloth_id` coverage
  and compares objective, period, list/detail, and budget evidence
- `slo-rules-engine/sloth-mcp-comparison/v1` links exact source fingerprints,
  retains bounded provider evidence and stable drift findings, omits endpoint
  and provider-controlled free text, and declares
  `authoritative_status_transport: false`
- The Human `sloth-mcp compare` command and planned Agent JSON request are
  registered together; matched output exits zero, saved semantic drift exits
  one, and contract/evidence failures write no report
- `sloth-evidence capture` now creates reviewed, content-addressed,
  credential-free generated-rule evidence without executing Sloth or reading a
  backend
- Sloth evidence capture structurally parses safe YAML, links canonical
  manifest/native/generated fingerprints, requires exact reviewed SLO
  coverage, and rejects missing, ambiguous, unrelated, or inconsistent records
- Sloth evidence retains exact provider record selectors for objective,
  allowed/remaining budget, current/period burn, metadata, evaluation error
  ratio, and freshness; observations use the reviewed native total query rather
  than mislabeling an error ratio
- `sloth-evidence status` validates artifact schema and content identity before
  trusting source paths, then reports fresh/stale source checks with stable
  findings and no provider I/O
- The shared Human/Agent command registry/catalog now contains 40 commands,
  including matching Human CLI and planned Agent JSON mappings for Sloth
  evidence capture/status and MCP comparison
- AICLI-F1 now provides immutable `CommandDefinition` values, a validated
  40-command `CommandRegistry`, and a separate versioned `CommandCatalog` that
  pairs current Human CLI examples with planned Agent CLI JSON requests
- Human top-level and grouped subcommand dispatch now resolve through the
  registry, so an unregistered Human command is unreachable; existing command
  handlers, stdout, exit codes, provider behavior, and safety gates are unchanged
- Registry coverage requires stable IDs/versions, Human and Agent mappings,
  request/result/error contract references, side-effect class, local/provider
  I/O, credential categories, safety gates, output controls, and MCP metadata
- AICLI-F2 runtime introspection now provides bounded deterministic offline
  catalog pagination, exact command descriptions, strict resolved request
  schemas for all 40 commands, and stable JSON-only introspection errors
- AICLI-F2 structured invocation now accepts exactly one complete inline JSON,
  workspace-file, or stdin request for seven commands, validates it
  against the registered strict schema, applies explicit/environment/default
  JSON format precedence, and returns deterministic result/error envelopes
- Human and Agent provider/integration listing, calculation-basis
  recommendation, definition validation, migration/model reporting, and
  file-backed diff now share typed application commands that return values
  without printing or exiting; other registered commands fail with
  `agent_command_not_executable` before their handlers run
- AICLI-F3 read safety now confines Agent file inputs and managed roots to the
  workspace, rejects traversal, absolute/pre-encoded/control-character paths,
  checks symlink containment and `.rb`/`.json` types, bounds count/bytes,
  validates all diff paths before manifest content, and quarantines direct
  application output/exit attempts
- The STR-3 catalog contract family now authors `providers.list`,
  `integrations.list`, and `generate-routes` once with Human usage, Agent
  examples, and explicit request schemas; the analysis and provider-state
  families now do the same, while remaining families retain the compatibility
  assembly
- A repository-wide structure audit maps all 19 use cases, 40 commands, the
  original 20 literal versioned production schema identifiers, dependency cycles, duplicated
  artifact policy, responsibility hotspots, freeze zones, and eight reversible
  STR packets with packet-specific verification and rollback gates
- Phase 14 now has an article-derived, revalidated roadmap for a shared command
  registry, feature-parity Human/Agent CLI adapters, strict structured
  requests, runtime schema introspection, bounded/sanitized output,
  adversarial input validation, zero-I/O validation, agent skill distribution,
  headless credentials, and later MCP projection; runtime introspection plus
  the zero-I/O and first workspace-read/state-plan slices are implemented while
  broader invocation and later capabilities remain open
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
  for every Prometheus Stack and evidence-backed Sloth target, validates all
  mappings before constructing a client, and never persists runtime URLs
- Aggregate reports preserve complete target reports, deterministic target and
  five-state rollups, explicit unsupported Datadog and Sloth-without-evidence
  coverage, and one target's query failures as `unverifiable` without dropping
  successful targets
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

- latest checkpoint: workspace-confined Agent validation/reporting and
  file-backed state diff with Human result/exit parity and explicit STR-3
  analysis/provider-state contracts
- previous checkpoint: strict zero-I/O Agent JSON/file/stdin invocation with
  deterministic envelopes, typed Human/Agent application commands, and the
  first single-declaration STR-3 command family
- previous checkpoint: STR-0 deterministic architecture fitness, exact
  dependency-debt allowlisting, contract snapshots, and complete
  registry-derived command-module ownership
- previous checkpoint: evidence-based whole-project structure refactoring plan
  with eight reversible packets and all-use-case preservation mapping
- previous checkpoint: AICLI-F2 bounded offline runtime introspection and strict
  resolved request schemas across the 40-command registry
- previous checkpoint: official Sloth MCP read-only comparison with exact evidence,
  capability/schema, identity, bounded-output, and Human/Agent parity gates
- previous checkpoint: opt-in evidence-backed Sloth downstream release
  verification with complete readable-state evidence
- previous checkpoint: release/portfolio packaging and aggregate status for
  current exact Sloth downstream evidence
- previous checkpoint: evidence-backed one-manifest Sloth live status and official
  Sloth MCP integration path
- previous checkpoint: reviewed content-addressed Sloth downstream generated-rule
  evidence plus local source freshness status
- previous checkpoint: AICLI-F1 shared command registry and separate 38-command
  Human CLI to planned Agent JSON parity catalog
- previous checkpoint: article-derived Agent Interface Roadmap with complete
  current-command parity inventory, requirements, feature packets,
  architecture, use case, and permanent dual-interface maintenance rule
- previous checkpoint: read-only file-backed bundle verification and immutable
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

1. Extend AICLI-F3 to output-root confinement and zero-I/O `validate_only`
   before enabling the first Agent local-write command family; add URL/host and
   resource-ID rules before provider-read commands that need them
2. Continue STR-3 one command family at a time until every command owns its
   Human usage, Agent example, explicit schema, side effects, I/O, safety,
   contract references, and MCP metadata in one declaration
3. Run the Datadog sandbox probes and resume live provider-contract work only
   when the user makes credentials/evidence available
4. Extend exact approval/apply/resume to Datadog only after verified backend
   recheck and idempotency semantics exist
5. Revalidate Sloth MCP against a tagged official binary and real Prometheus
   data only after a release contains the MCP surface; do not promote status
   while observations, exact record identity, and equivalent freshness are absent
6. Add automatic rollback execution only after a reviewed compensating-plan
   contract exists; current exact failures provide manual guidance

Secondary gaps:

1. Broader state-management parity for future providers after Datadog and Prometheus Stack prove the shared contract
2. Automatic rollback execution only after a reviewed compensating-plan
   contract exists; current exact failures provide manual guidance
3. Execute STR-1 through STR-7 only with the plan's named dependencies,
   preservation, verification, compatibility-facade, and rollback gates

## Recommended Next Slice

Next recommended slice:

- add confined output-root validation and a zero-I/O `validate_only` contract
  for the first local-write generation/review command family
- migrate that affected command family to explicit STR-3 declarations in the
  same slice; do not reconstruct Human `argv` in the Agent adapter

Rationale:

- the supported Sloth boundary is complete through generation, file-state
  planning/exact execution, downstream evidence, direct and aggregate neutral
  status, release verification, and official MCP comparison
- the MCP comparison detects provider identity/objective/period/budget drift
  without weakening source freshness, exact-record, status, or mutation gates
- remaining Sloth work is externally gated on a tagged MCP release and additional
  upstream status evidence, not an unfinished engine feature
- AICLI-F2 now has a complete 40-command registry/catalog/introspection
  foundation plus proven zero-I/O and workspace-read/state-plan paths
- file-reading validation/reporting and local file-backed diff now have shared
  path/input validation; local writes and provider mutation remain correctly
  gated on the rest of AICLI-F3
- STR-0 now prevents new cross-layer debt and locks the current command, schema,
  use-case, boundary, and command-module inventories before feature growth
- the refactoring plan revalidated every hotspot against all 19 use cases and
  explicitly freezes stable DSL, Datadog, onboarding, and validator code
- Datadog work remains correctly evidence-gated and postponed

## Next Session Handoff

Prepared on 2026-08-15 for a restart-and-`proceed` workflow.

Current safe boundary:

- branch: `main`
- latest pushed checkpoint: `feat: harden agent read commands`
- previous pushed checkpoint: `9cb5056 feat: add strict agent invocation`
- expected startup state: `git status --short --branch` should show clean
- last full verification before handoff:
  `PATH=/opt/homebrew/opt/ruby/bin:$PATH ./scripts/verify.sh` exited 0 with
  `verification ok`

Verification evidence:

- target: workspace-confined Agent read commands, file-backed state diff, and
  explicit analysis/provider-state STR-3 contract families
- command: `PATH=/opt/homebrew/opt/ruby/bin:$PATH ./scripts/verify.sh`
- recorded date: `2026-08-15`
- output path: agent terminal transcript; no separate repository artifact persisted
- result: exit 0, `verification ok`, 513 tests, 7,025 assertions, 0 failures,
  0 errors, 0 skips
- focused result: Agent invocation passed with 7 tests and 116 assertions;
  Agent read/path safety passed with 9 tests and 105 assertions;
  registry/contracts passed with 8 tests and 2,670 assertions; introspection
  passed with 5 tests and 378 assertions; architecture fitness passed with 5
  tests and 26 assertions; all had zero failures, errors, and skips
- structural evidence: `scripts/structure-report --check` passed with 94
  production files, 40 commands, 21 unique literal artifact schemas, 120
  per-command schema references, 19 use cases, complete
  single-boundary file ownership, and exact dependency-debt references
- parity evidence: SHA-256 snapshots cover the full registry and Human/Agent
  catalog, all 40 command IDs are unchanged, and all 11 focused CLI command
  modules own at least one registered adapter
- runtime note: macOS system Ruby 2.6.10 lacks `Array#filter_map`, already used
  throughout the repository; the canonical suite passed with installed Ruby
  4.0.1. No runtime compatibility code was changed in this implementation slice.
- metric/log/trace names: none; verification used local files and fake backend
  clients only
- offline verification: Human/Agent parity covers validation, migration/model
  reports, and Prometheus Stack file-backed diff; traversal, absolute,
  pre-encoded, control-character, symlink-escape, oversized, and unsafe
  multi-path inputs fail as JSON before content/provider access; direct
  application stdout/stderr is quarantined
- live verification: no tagged Sloth binary contains MCP, so a full comparison
  against a released server and real Prometheus data could not be run. Latest
  observed release `v0.16.0` is intentionally rejected. Datadog live testing
  remains postponed.
- blast radius: Agent input/path validation and envelopes, four additional
  typed read commands, analysis/provider-state declarations, Human adapter
  delegation, architecture snapshots, tests, and usage. No provider artifact,
  network call, local/provider mutation, or external dependency was added.
- rollback path: revert `feat: harden agent read commands`

When the user types `proceed` in a fresh session:

1. First read this file, `docs/implementation-plan.md`, `docs/adoption-map.md`, and the latest 5-10 commits.
2. Confirm the worktree is clean with `git status --short --branch`.
3. Read `docs/housekeeping/project-structure-refactoring-plan.md`; STR-0 is
   complete, so preserve its checks while implementing the next vertical slice.
4. Treat the supported Sloth engine boundary as complete; do not invent more
   provider work while the tagged MCP release and status-parity fields are absent.
5. Extend AICLI-F2 only after adding the AICLI-F3 validation required by the
   next command's output/URL/ID fields; do not reconstruct Human `argv` inside
   the Agent adapter.
6. Preserve the completed AICLI-F1 registry/catalog parity and update both the
   Human CLI usage and target Agent JSON mapping for every CLI change.
7. Keep the official Sloth MCP runtime comparison-only and do not claim status
   parity while observations, exact record identity, and equivalent freshness
   are absent.
8. Keep Datadog live testing postponed unless the user explicitly reopens it
   with isolated credentials/evidence.
9. Preserve release-bundle predecessor immutability, exact-plan, review,
   journal, live-status, and mutation gates exactly.

## Verification Commands

Use these before claiming a checkpoint:

```bash
ruby -Ilib test/project_refactoring_plan_test.rb
ruby -Ilib test/architecture_fitness_test.rb
ruby -Ilib test/agent_introspection_test.rb
ruby -Ilib test/agent_invocation_test.rb
ruby -Ilib test/agent_read_commands_test.rb
ruby -Ilib test/agent_interface_roadmap_test.rb
ruby -Ilib test/cli_command_registry_test.rb
ruby -Ilib test/sloth_mcp_client_test.rb
ruby -Ilib test/sloth_mcp_comparison_test.rb
ruby -Ilib test/sloth_mcp_cli_test.rb
ruby -Ilib test/sloth_downstream_evidence_test.rb
ruby -Ilib test/sloth_downstream_evidence_cli_test.rb
ruby -Ilib test/sloth_live_status_test.rb
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
PATH=/opt/homebrew/opt/ruby/bin:$PATH ./scripts/verify.sh
scripts/structure-report --check
git status --short --branch
```

## Resume Checklist

If a new session needs to resume quickly:

1. Read this file
2. Read `docs/implementation-plan.md`
3. Read `docs/adoption-map.md`
4. Read the latest 5-10 commits on `main`
5. Read `docs/housekeeping/project-structure-refactoring-plan.md`, then read
   `docs/agent-interface-roadmap.md` for the completed AICLI-F1 and
   AICLI-F2 introspection, zero-I/O, and workspace-read boundaries plus remaining
   command gates
6. Inspect `lib/slo_rules_engine/application/input_safety.rb`,
   `lib/slo_rules_engine/application/commands.rb`,
   `lib/slo_rules_engine/cli/command_registry.rb`,
   `lib/slo_rules_engine/cli/agent_introspection.rb`, and
   `lib/slo_rules_engine/cli/agent_invocation.rb`, plus
   `test/agent_invocation_test.rb` and `test/agent_read_commands_test.rb` before
   changing any CLI surface
7. Inspect `lib/slo_rules_engine/live_status/sloth_reader.rb`,
   `lib/slo_rules_engine/sloth/downstream_evidence.rb`, and
   `docs/sloth-mcp-integration.md`
8. If the user says `proceed`, add output-root/validation-only safety and expand
   AICLI-F2 through the next typed STR-3 command family; the supported Sloth
   comparison boundary is implemented and a tagged-runtime parity test is
   externally gated
9. Update both CLI sub-interface mappings and usage for every CLI change; do not
   add independent adapter business logic
10. Keep the official Sloth MCP adapter comparison-only; the current
   Prometheus-compatible evidence reader remains authoritative for neutral
   live status and release verification
11. Keep Datadog live testing postponed and preserve every exact-plan, review,
   journal, live-status, and mutation gate
