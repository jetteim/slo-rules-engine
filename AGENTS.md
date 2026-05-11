# AGENTS.md

## Purpose

This repository is a public-safe SLO rules engine.

It models provider-independent reliability intent in a Ruby DSL, generates provider-specific observability artifacts, and is being deepened into an explicit provider-state management engine with `diff`, `import`, `apply`, and `prune`.

## Current Priority Order

1. Provider-state deepening
2. Telemetry-first onboarding path
3. Provider breadth and telemetry-first scale after the baseline is solid

The current stream is provider-state deepening. Do not switch to telemetry-first work until the current provider-state checkpoint is at a safe commit/push boundary.

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

## Most Recent Checkpoints

- `4630f3e` `feat: report orphan datadog backend resources on import`
- `20b5d23` `feat: prune orphan datadog managed resources`
- `adf5f9b` `fix: skip noop manifest bundle apply operations`
- `b65acb2` `feat: report missing datadog backend resources on import`
- `67ecfd3` `fix: skip noop datadog apply operations`
- `a609161` `feat: validate datadog live apply payloads`

## Current Open Gaps

Highest-value remaining provider-state gaps:

1. Broaden Datadog `time_slice` translation beyond counter-ratio and threshold-based single-query inputs to the remaining reviewed intent shapes
2. Remaining Datadog resource semantics not yet validated against the real backend contract, especially dashboard structure and any provider-owned fields still treated heuristically
3. Broader state-management parity for future providers after the Datadog baseline is stronger

Secondary gaps:

1. Batch telemetry discovery across service portfolios and selector inputs
2. Candidate confidence and saved evidence packets for telemetry-derived drafts
3. Add anonymization helper for examples

## Recommended Next Slice

Next recommended provider-state slice:

- broaden real Datadog payload translation coverage beyond the current counter-ratio and threshold-based `time_slice` SLO baseline while keeping backend-state reconciliation strict

Rationale:

- managed identity tags and core SLO/monitor semantics are now validated before live apply
- counter-ratio `time_slice` SLOs now translate and reconcile cleanly
- threshold-based `time_slice` SLOs backed by provider query expressions now translate and reconcile cleanly
- dashboard evidence queries now preserve reviewed selector scope instead of drifting to provider-binding-only scope
- the next meaningful gap is closing the remaining distance between reviewed intent and actual Datadog backend semantics for the other `time_slice` and provider-owned payload shapes

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
3. Read the latest 5-10 commits on `main`
4. Inspect `lib/slo_rules_engine/appliers/datadog.rb`
5. Continue the highest-priority open slice listed above
