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

## Most Recent Checkpoints

- `4630f3e` `feat: report orphan datadog backend resources on import`
- `20b5d23` `feat: prune orphan datadog managed resources`
- `adf5f9b` `fix: skip noop manifest bundle apply operations`
- `b65acb2` `feat: report missing datadog backend resources on import`
- `67ecfd3` `fix: skip noop datadog apply operations`
- `a609161` `feat: validate datadog live apply payloads`

## Current Open Gaps

Highest-value remaining provider-state gaps:

1. Datadog provider-schema payload translation and backend-state reconciliation beyond the current heuristic baseline
2. Stronger Datadog resource identity fidelity where ownership still depends on generated names
3. Broader state-management parity for future providers after the Datadog baseline is stronger

Secondary gaps:

1. Batch telemetry discovery across service portfolios and selector inputs
2. Candidate confidence and saved evidence packets for telemetry-derived drafts
3. Add anonymization helper for examples

## Recommended Next Slice

Next recommended provider-state slice:

- tighten Datadog provider payload/state reconciliation so imported backend resources compare by managed semantics, not only by generated shape

Rationale:

- dashboard ownership now matches the tag-based model used for SLOs and monitors
- the next meaningful gap is translating generated resources into a stricter provider-state contract for import, diff, apply, and prune

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
