# AGENTS.md

## Purpose

This repository is a public-safe SLO rules engine.

It models provider-independent reliability intent in a Ruby DSL, generates provider-specific observability artifacts, and is being deepened into an explicit provider-state management engine with `diff`, `import`, `apply`, and `prune`.

## Current Priority Order

1. First-class onboarding and release bundle
2. Provider-neutral state-manager hardening
3. Production-grade Datadog reconciliation
4. Apply-exact-plan workflow
5. Live SLO and error-budget status

The release-bundle planning boundary is implemented. New slices should follow the accepted sequence above and should not resume housekeeping or opportunistic provider work.

Current release-bundle status: `slo-rules-engine/release-bundle/v1` packages discovery evidence, reviewed handoffs and definitions, provider manifests, fresh manifest-review reports, and dry-run plans into a content-addressed JSON document. It records explicit reviewer attestation, lifecycle state, provider targets, artifact fingerprints, transition lineage, and provider-level change and risk summaries without credentials. `bundle create` is fail-closed for incomplete, stale, invalid, or credential-bearing input. `bundle plan` rechecks predecessor freshness, requires explicit runtime configuration for every target, leaves the predecessor immutable, performs no provider mutation, and writes a new content-addressed `apply_ready` bundle. `bundle status` detects schema errors, embedded tampering, identity mismatch, missing sources, and source drift.

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
- Each reviewed Prometheus SLO now has derived success-ratio, error-ratio, objective-ratio, error-budget-ratio, and burn-rate recording rules
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

## Most Recent Checkpoints

- latest checkpoint: immutable bundle-native provider planning and provider-level impact/risk summaries
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

1. Define and prove provider-neutral desired-state, observed-state, change, result, and finding contracts
2. Add execution journaling, partial-failure reporting, and provider verification evidence on those contracts
3. Validate remaining Datadog resource semantics against safe real-backend evidence after shared state contracts are stronger
4. Persist and execute an exact reviewed plan with stale-state rejection
5. Expose live SLO and error-budget status without weakening provider-neutral intent

Secondary gaps:

1. Broader state-management parity for future providers after Datadog and Prometheus Stack prove the shared contract
2. Additional CLI command extraction only when the bundle or state features expose a clean ownership boundary
3. Additional provider breadth only after the accepted feature sequence above

## Recommended Next Slice

Next recommended slice:

- start Phase 10 by defining provider-neutral desired-state, observed-state, change, result, and finding value contracts
- adapt existing Datadog and Prometheus Stack planning evidence to those contracts without changing provider mutation behavior
- preserve provider-owned payloads, ownership policy, and risk metadata rather than flattening them into generic policy
- use public-safe fixtures to prove both providers can cross the shared boundary
- do not add `bundle apply`, operation journaling, or exact-plan execution in the same foundational slice

Rationale:

- bundle planning now proves the reviewed bundle-to-provider planning boundary without mutation
- the planned bundle preserves provider operations and risk evidence but the shared state vocabulary is still implicit in `ApplyPlan`, imported state, and provider-specific hashes
- formal value contracts are required before journaling, resumability, verification results, or bundle apply can be implemented coherently
- Datadog and Prometheus Stack already provide sufficiently different state mechanisms to expose weak abstractions early
- exact-plan execution remains a separate Phase 12 guarantee and must not be implied by the first state-contract slice

## Next Session Handoff

Prepared on 2026-07-26 for a restart-and-`proceed` workflow.

Current safe boundary:

- branch: `main`
- latest verified feature checkpoint: `a769eea feat: add release bundle create and status`
- expected startup state: `git status --short --branch` should show clean `main...origin/main`
- last full verification before handoff: `./scripts/verify.sh` exited 0 with `verification ok`

Verification evidence:

- target: local `main` worktree at `a769eea`
- command: `./scripts/verify.sh`
- timestamp: `2026-07-26T10:26:20Z`
- output path: agent terminal transcript; no separate repository artifact persisted
- result: exit 0, `verification ok`, 304 tests, 1,633 assertions, 0 failures, 0 errors
- metric/log/trace names: none; this slice made no backend calls
- blast radius: explicitly requested release-bundle JSON output plus local source-file reads
- rollback path: revert `a769eea` and `cbf271c`; no provider or managed-file rollback is required

When the user types `proceed` in a fresh session:

1. First read this file, `docs/implementation-plan.md`, `docs/adoption-map.md`, and the latest 5-10 commits.
2. Confirm the worktree is clean with `git status --short --branch`.
3. Do not resume housekeeping by default.
4. Start Phase 10 with provider-neutral state value contracts and adapters over current plan/import evidence.
5. Use TDD to prove Datadog and Prometheus Stack retain provider-specific payload, identity, finding, and risk evidence through the shared contracts.
6. Do not change live mutation behavior or add `bundle apply` in the foundational contract slice.

## Verification Commands

Use these before claiming a checkpoint:

```bash
ruby -Ilib test/prometheus_stack_provider_test.rb
ruby -Ilib test/prometheus_stack_walkthrough_test.rb
ruby -Ilib test/release_bundle_test.rb
ruby -Ilib test/release_bundle_cli_test.rb
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
5. Inspect `lib/slo_rules_engine/release_bundle`, `lib/slo_rules_engine/cli/bundle_commands.rb`, and their tests
6. Inspect `lib/slo_rules_engine/apply.rb`, both provider appliers, and `docs/release-bundle-contract.md`
7. If the user says `proceed`, follow the Phase 10 handoff above
8. Keep Phase 11 Datadog reconciliation, Phase 12 exact-plan execution, and Phase 13 live status in the accepted order
