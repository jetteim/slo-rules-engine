# Abstraction Layer Review

Review date: 2026-06-01

Scope: recommendation-only housekeeping review. No production abstraction changes were made for this review.

## Completion Update: 2026-07-28

The original pressure points were re-audited after the release-bundle,
provider-state, exact-plan, and live-status feature sequence:

- Datadog payload translation, risk policy, state planning, state reading, and
  request transport are now focused collaborators behind the stable applier and
  client facades
- onboarding, catalog, telemetry, report, bundle, journal, approved-plan, and
  status commands now have focused command-family modules
- `bin/rules-ctl` is now a thin bootstrap; reusable orchestration lives at
  `lib/slo_rules_engine/cli.rb`
- shared manifest/state helpers remain in the CLI library facade because they
  intentionally preserve common loading, validation, freshness, error, and
  usage behavior across command families
- large provider-state journal/execution, DSL, and manifest-review files remain
  intact where splitting by line count would increase semantic risk without
  removing a responsibility

The current layer map, dependency rules, flows, and safety boundaries are in
[`docs/design.md`](../design.md). The requirement/component/test decision record
is
[Atomic Coherence-Preserving Simplification](atomic-coherence-simplification.md).
This abstraction review is complete. Future extraction requires a new focused
responsibility and characterization evidence, not a file-size threshold.

## Current Layer Map

Core model and DSL:

- `lib/slo_rules_engine/model.rb`, `lib/slo_rules_engine/reliability_model.rb`, `lib/slo_rules_engine/validation.rb`, and `lib/slo_rules_engine/dsl/service_definition.rb` hold provider-neutral reliability intent, DSL parsing, and validation.

Provider contract and generation:

- `lib/slo_rules_engine/provider.rb`, `lib/slo_rules_engine/providers/*.rb`, `lib/slo_rules_engine/integration.rb`, and `lib/slo_rules_engine/integrations/notification_router.rb` define provider/integration boundaries and manifest generation.

Provider state and mutation:

- `lib/slo_rules_engine/apply.rb`, `lib/slo_rules_engine/appliers/manifest_bundle.rb`, `lib/slo_rules_engine/appliers/datadog.rb`, `lib/slo_rules_engine/datadog/client.rb`, `lib/slo_rules_engine/datadog/payload_canonicalizer.rb`, and `lib/slo_rules_engine/datadog/payload_validator.rb` handle state planning, backend comparison, payload validation, and mutation.

Telemetry and onboarding:

- `lib/slo_rules_engine/telemetry_lookup*.rb`, `lib/slo_rules_engine/telemetry_batch_discovery.rb`, `lib/slo_rules_engine/reality_check.rb`, and `lib/slo_rules_engine/onboarding/*.rb` hold lookup adapters, batch discovery, candidate generation, saved handoff, reviewed draft generation, validation, and artifact indexing.

Review and CLI handoff:

- `lib/slo_rules_engine/manifest_review_queue.rb`, `lib/slo_rules_engine/manifest_review_evidence.rb`, `lib/slo_rules_engine/manifest_schema.rb`, and `bin/rules-ctl` connect reviewed evidence to provider artifact queues and command workflows.

## Findings

### Blockers

- None. The current layers support the telemetry-first milestone and Datadog safety baseline.

### Important Gaps

- `bin/rules-ctl` is doing too much: argument parsing, command dispatch, orchestration, JSON rendering, file writes, provider selection, review freshness checks, and error rendering are coupled in one executable file.
- `SloRulesEngine::Appliers::Datadog` is too broad for its current responsibility set. It combines state planning, payload translation, backend identity policy, risk signaling, query inference, payload comparison, and live mutation sequencing.
- `SloRulesEngine::Datadog::Client` combines HTTP transport/retry behavior with backend state discovery, managed-resource filtering, import matching, delete helpers, and create-and-wait polling.
- `lib/slo_rules_engine/manifest_review_queue.rb` now contains queue building, report metadata, handoff linking, fingerprinting, and freshness validation. This is still readable, but it is a low-risk candidate for file-level separation if it grows again.
- `lib/slo_rules_engine/dsl/service_definition.rb` has many nested DSL builders in one file. Splitting it now is not urgent because the DSL surface is stable, but future DSL expansion should avoid growing this file further.
- `SloRulesEngine::Onboarding::SummaryBuilder` now summarizes saved discovery evidence and writes handoff packets. This remains acceptable, but more handoff-writing behavior should move behind a small packet writer.

## Recommendations

1. Start with test support extraction before production abstraction refactors. That reduces review risk and gives characterization coverage for later file moves.
2. Extract CLI command objects or modules under `lib/slo_rules_engine/cli/` or `lib/slo_rules_engine/commands/`, leaving `bin/rules-ctl` as dispatch, usage, exit handling, and JSON output plumbing.
3. Prioritize command extraction around high-churn flows first: manifest review, onboarding artifact index, handoff review/validation, and state commands. These are where the CLI file currently grows fastest.
4. Split Datadog applier internals behind private collaborators before making new public abstractions. Candidate collaborators: `Datadog::PlanBuilder`, `Datadog::PayloadTranslator`, `Datadog::IdentityPolicy`, `Datadog::RiskPolicy`, and `Datadog::MutationRunner`.
5. Keep the current Datadog applier facade stable while splitting internals. Existing callers should still use `SloRulesEngine::Appliers::Datadog` for `plan`, `diff`, `import`, `apply`, and `prune`.
6. Split `Datadog::Client` into a transport facade and state reader only after Datadog tests are split. Candidate collaborators: `Datadog::HttpTransport`, `Datadog::StateReader`, and `Datadog::ManagedStateReader`.
7. Split `manifest_review_queue.rb` only if more review metadata is added. Suggested files: `manifest_review_queue/report_builder.rb` and `manifest_review_queue/freshness_validator.rb`.
8. Keep provider generators compact and provider-neutral for now. `providers/datadog.rb`, `providers/prometheus_stack.rb`, and `providers/sloth.rb` are not the current abstraction pressure point.
9. Keep `notification_router` as an integration, not a provider. No new abstraction is needed there.

## Accepted Deferrals

- Do not refactor Datadog applier/client until the test suite has support helpers and clearer Datadog test boundaries.
- Do not split the DSL builder file just to reduce line count. Split only when a new DSL feature creates a focused extraction seam.
- Do not promote onboarding artifact indexing out of the onboarding layer unless non-onboarding artifact bundles start using it.
- Do not add provider-state abstractions for future providers before another provider needs them.

## Suggested Extraction Order

1. Pilot test support helpers for CLI and onboarding fixtures.
2. Extract CLI command modules for review and onboarding flows while preserving `bin/rules-ctl` behavior.
3. Split `manifest_review_queue.rb` if review freshness logic grows again.
4. Split Datadog applier internals by behavior after the Datadog tests are easier to navigate.
5. Split Datadog client transport/state-reader concerns after applier internals are stable.

## Next Useful Slice

The next implementation slice should not start with Datadog abstraction refactoring. It should first compact test support around CLI and onboarding fixtures, then use the cleaner tests as guardrails for CLI command extraction.
