# AGENTS.md

## Purpose

This repository is a public-safe SLO rules engine.

It models provider-independent reliability intent in a Ruby DSL, generates provider-specific observability artifacts, and is being deepened into an explicit provider-state management engine with `diff`, `import`, `apply`, and `prune`.

## Current Priority Order

1. Provider-state deepening
2. Telemetry-first onboarding path
3. Remaining DSL compatibility and migration helpers

The current stream is provider-state deepening. Do not switch to telemetry-first work until the current provider-state checkpoint is at a safe commit/push boundary.

## Non-Negotiable Working Rules

- Keep the repo public-safe. Private/internal rules are reference material only and must not be copied in.
- Prefer the existing neutral DSL and provider contract over provider-specific policy.
- Commit and push often.
- Add verification evidence before claiming a checkpoint is complete.
- Update this file when a checkpoint materially changes current priorities, recent checkpoints, or the next recommended slice.

## Trusted External Reference

Use this private repo as the authoritative behavioral reference for Datadog state-management semantics:

- `~/OneDrive/NEW_WORK/sre-rules`

Treat it as evidence for generalized OSS-safe behavior, not as source text to copy directly.

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

## Most Recent Checkpoints

- `4630f3e` `feat: report orphan datadog backend resources on import`
- `20b5d23` `feat: prune orphan datadog managed resources`
- `adf5f9b` `fix: skip noop manifest bundle apply operations`
- `b65acb2` `feat: report missing datadog backend resources on import`
- `67ecfd3` `fix: skip noop datadog apply operations`
- `a609161` `feat: validate datadog live apply payloads`

## Current Open Gaps

Highest-value remaining provider-state gaps:

1. Datadog ownership/identity fidelity, especially dashboards
2. Datadog provider-schema payload translation and backend-state reconciliation beyond the current heuristic baseline
3. Broader state-management parity for future providers after the Datadog baseline is stronger

Secondary gaps:

1. Expand DSL compatibility to match more of the legacy definition shape
2. Add anonymization helper for examples
3. Add import guidance for existing service files

## Recommended Next Slice

Next recommended provider-state slice:

- replace dashboard ownership heuristics based on generated description text with explicit dashboard ownership metadata and matching discovery logic

Rationale:

- current Datadog dashboard managed-state discovery works, but its ownership signal is weaker than the SLO/monitor tag-based model
- this is the next smallest step that materially improves reconciliation fidelity

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
