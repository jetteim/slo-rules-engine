# AGENTS.md

## Purpose

This repository is a public-safe SLO rules engine.

It models provider-independent reliability intent in a Ruby DSL, generates provider-specific observability artifacts, and is being deepened into an explicit provider-state management engine with `diff`, `import`, `apply`, and `prune`.

## Current Priority Order

1. Telemetry-first onboarding path
2. Provider-state follow-up hardening if new backend evidence exposes a concrete safety gap
3. Provider breadth after the telemetry-first baseline is stronger

The provider-state deepening checkpoint is now at a safe commit/push boundary. New slices should default to telemetry-first onboarding unless fresh Datadog evidence reveals a concrete backend-contract gap.

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

## Most Recent Checkpoints

- latest: `fix: detect ambiguous datadog identity matches`
- previous: `fix: require managed tags for datadog fallback matches`
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

Highest-value remaining provider-state gaps:

1. Remaining Datadog resource semantics not yet validated against the real backend contract, especially any provider-owned fields still treated heuristically
2. Batch telemetry discovery and review-readiness ranking for service portfolios
3. Candidate confidence and saved evidence packets for telemetry-derived drafts

Secondary gaps:

1. Broader state-management parity for future providers after the Datadog baseline is stronger
2. Service onboarding summary that ranks discovered services and signals by review readiness
3. Optional live Datadog contract verification when credentials and safe backend access are available

## Recommended Next Slice

Next recommended slice:

- start telemetry-first onboarding depth with batch discovery across service portfolios and selector inputs

Rationale:

- the shared change-impact summary baseline now exists across `diff`, `apply`, and `prune`
- provider-specific risk signaling now exists for recreate and prune-delete operations
- weaker identity matches are now explicit in import and plan output
- live Datadog `update` and `recreate` now enforce managed source identity
- low-confidence prune deletes now use the same enforcement threshold
- fallback name/title matching no longer claims ownership of unmanaged SLOs or dashboards
- duplicate source identity now degrades to weak ownership instead of silently selecting an arbitrary backend match
- the remaining Datadog contract gaps are now narrower than the telemetry-first adoption gap
- Datadog remains the reference live provider, but follow-up hardening can now be evidence-driven instead of roadmap-leading

## Verification Commands

Use these before claiming a checkpoint:

```bash
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
5. Inspect `lib/slo_rules_engine/appliers/datadog.rb`
6. Continue the highest-priority open slice listed above
