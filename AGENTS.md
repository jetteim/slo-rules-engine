# AGENTS.md

## Purpose

This repository is a public-safe SLO rules engine.

It models provider-independent reliability intent in a Ruby DSL, generates provider-specific observability artifacts, and is being deepened into an explicit provider-state management engine with `diff`, `import`, `apply`, and `prune`.

## Current Priority Order

1. Telemetry-first onboarding path
2. Provider-state follow-up hardening if new backend evidence exposes a concrete safety gap
3. Provider breadth after the telemetry-first baseline is stronger

The provider-state deepening checkpoint is now at a safe commit/push boundary. New slices should default to telemetry-first onboarding unless fresh Datadog evidence reveals a concrete backend-contract gap.

Current telemetry-first status: the onboarding path now carries saved discovery evidence through candidate confidence, handoff review, reviewed draft generation, provider manifest review, saved report freshness checks, live mutation gates, a compact artifact index, and an end-to-end public-safe walkthrough smoke test. A provider-breadth checkpoint now strengthens Sloth external-generator handoff by writing native Sloth spec input files. Housekeeping is ready to resume next with low-risk test support extraction before CLI or Datadog abstraction refactors unless new backend evidence exposes a provider-state gap.

## Non-Negotiable Working Rules

- Keep the repo public-safe. Private/internal rules are reference material only and must not be copied in.
- Prefer the existing neutral DSL and provider contract over provider-specific policy.
- Commit and push often.
- Add verification evidence before claiming a checkpoint is complete.
- Update this file when a checkpoint materially changes current priorities, recent checkpoints, or the next recommended slice.

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

Implemented by the latest telemetry-first and provider-breadth slices:

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
- `docs/telemetry-first-walkthrough.md` and `test/telemetry_first_walkthrough_test.rb` now cover the saved-artifact flow through reviewed provider gates without live backend credentials
- `docs/housekeeping/test-suite-compaction-review.md` maps test-suite dependency shape and recommends compaction steps without changing test behavior
- `docs/housekeeping/abstraction-layer-review.md` maps abstraction layer pressure points and recommends extraction order without changing production code
- Sloth external-generator apply now writes native Sloth `prometheus/v1` YAML input files, includes them in plans/diffs/prune operations, and points handoff commands at those files while preserving the reviewed engine manifest as provenance
- Test support guardrails now include CLI helpers, onboarding handoff/discovery fixtures, and shared Datadog fake client/response fixtures
- Onboarding-related CLI commands now live in `lib/slo_rules_engine/cli/onboarding_commands.rb` instead of `bin/rules-ctl`

## Most Recent Checkpoints

- latest checkpoint: CLI/onboarding/Datadog test guardrails plus onboarding CLI command extraction
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

1. Split `test/datadog_apply_test.rb` by behavior using extracted Datadog fakes as guardrails
2. Use the split Datadog tests before Datadog applier/client abstraction splits
3. Remaining Datadog resource semantics not yet validated against the real backend contract, especially any provider-owned fields still treated heuristically

Secondary gaps:

1. Broader state-management parity for future providers after the Datadog baseline is stronger
2. Optional live Datadog contract verification when credentials and safe backend access are available
3. Additional CLI command extraction as command families change
4. Additional provider breadth when a concrete reviewed handoff gap appears

## Recommended Next Slice

Next recommended slice:

- split `test/datadog_apply_test.rb` by behavior without changing assertions

Rationale:

- batch discovery now captures reusable normalized evidence for many scopes in one run
- onboarding summary now turns those saved results into a ranked review queue and can write handoff packets
- handoff review now records accepted/rejected candidate decisions
- reviewed drafts can now be generated from accepted handoff state without rerunning backend discovery
- handoff packets can now be validated before draft/provider handoff
- reviewed handoff provenance now flows through generated provider manifests
- live apply now requires reviewed handoff provenance before provider mutation or file-backed apply
- review summaries and model reports now make reviewed handoff provenance visible before provider generation
- manifest-review now checks provider artifact queues for missing or stale provenance before reviewers reach live apply
- saved manifest-review reports now persist next to generated manifests and can be written explicitly from saved manifest input
- handoff packet labels and files are now included in manifest-review findings when available
- manifest-review now detects when a manifest's embedded provenance no longer matches the latest reviewed handoff packet
- saved report path metadata now gives handoff tooling a stable pointer to the review artifact
- confirmed apply and prune now block stale-provenance evidence when handoff packets are available
- deterministic manifest and handoff fingerprints now provide the basis for saved report freshness checks
- saved manifest-review reports can now be validated against current artifacts before reviewers rely on them
- external-generator handoffs now tell reviewers how to validate manifest-review freshness before downstream generation
- the artifact index now reduces operator glue by publishing a single map of saved onboarding and provider handoff artifacts
- the full saved-artifact walkthrough now starts from saved discovery evidence and ends at reviewed provider artifact gates
- housekeeping reviews now identify concrete compaction and layering follow-ups
- Sloth external-generator handoff now writes native provider input files instead of relying on the engine manifest as generator input
- CLI, onboarding, and Datadog fake test guardrails now exist
- onboarding CLI command extraction proves the CLI can be split safely in small command-family modules
- the next value is making the oversized Datadog characterization suite easier to navigate before Datadog applier/client internals are split
- Datadog remains the reference live provider, but follow-up hardening can stay evidence-driven instead of roadmap-leading

## Verification Commands

Use these before claiming a checkpoint:

```bash
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
5. Inspect `lib/slo_rules_engine/onboarding/summary_builder.rb`
6. Continue the highest-priority open slice listed above
