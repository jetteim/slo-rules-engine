# Test Suite Compaction Review

Review date: 2026-06-01

Scope: recommendation-only housekeeping review. No test or production behavior was changed for this review.

## Completion Update: 2026-07-28

The original recommendations have been re-audited against the current
post-feature repository:

- shared CLI, onboarding, release-bundle, and Datadog fixtures now exist under
  `test/support`
- Datadog coverage is split by payload translation, planning, state reading,
  transport, execution, and sandbox behavior while the aggregate entrypoint is
  preserved
- process-level `cli_test.rb` remains the user-visible command contract;
  `rules_ctl_test.rb` remains focused on injected internal error branches
- focused, aggregate, public-safety, and full verification tiers are documented
  in `AGENTS.md`
- the two one-purpose command-module ownership suites are consolidated into
  `cli_architecture_test.rb`, with the same ownership assertions plus explicit
  thin-executable coverage
- duplicated live-status service-manifest transformation now lives in
  `ReleaseBundleFixtures`

The current before/after metrics, test traceability, and accepted deferrals are
recorded in
[Atomic Coherence-Preserving Simplification](atomic-coherence-simplification.md).
No process-level safety, mutation, freshness, exact-plan, or live-status
coverage was removed. This recommendation review is complete; further test
compaction requires a concrete behavior change or demonstrated duplication.

## Evidence Snapshot

- Test suite size: 22 Ruby test files, 6,645 test lines.
- Largest suites: `test/datadog_apply_test.rb` at 2,056 lines, `test/cli_test.rb` at 1,662 lines, and `test/rules_ctl_test.rb` at 539 lines.
- Production hotspots that drive test setup complexity: `bin/rules-ctl` at 1,091 lines, `lib/slo_rules_engine/appliers/datadog.rb` at 998 lines, and `lib/slo_rules_engine/datadog/client.rb` at 505 lines.
- Current full verification path remains `ruby -Ilib test/all_test.rb`, `ruby -Ilib test/forbidden_terms_test.rb`, and `./scripts/verify.sh`.

## Test Topology

Unit and domain suites:

- `test/dsl_test.rb`, `test/validation_test.rb`, `test/reliability_model_test.rb`, `test/reality_check_test.rb`, and `test/migration_report_test.rb` cover neutral model, DSL, validation, reliability modeling, and public-safe migration checks.
- `test/provider_bindings_test.rb`, `test/providers_test.rb`, `test/manifest_schema_test.rb`, `test/apply_test.rb`, and `test/manifest_review_queue_test.rb` cover provider generation, provider contract, manifest shape, apply plans, and review evidence.
- `test/telemetry_lookup_test.rb`, `test/telemetry_batch_discovery_test.rb`, `test/onboarding_test.rb`, `test/onboarding_summary_test.rb`, `test/onboarding_handoff_test.rb`, `test/onboarding_artifact_index_test.rb`, and `test/telemetry_first_walkthrough_test.rb` cover the telemetry-first onboarding path.

Command and integration-style suites:

- `test/cli_test.rb` launches `bin/rules-ctl` in subprocesses with `Open3.capture3`, so it validates process-level CLI behavior, exit statuses, JSON output, file writes, and environment handling.
- `test/rules_ctl_test.rb` loads `bin/rules-ctl` in-process and uses stubs plus `capture_io`, so it is better suited for internal command branches and error rendering that are hard to trigger through a real process.
- `test/datadog_apply_test.rb` mixes Datadog plan construction, live mutation safety, payload validation, backend state matching, retry behavior, and fake client behavior in one large file.
- `test/all_test.rb` is the aggregate Ruby suite; `scripts/verify.sh` adds CLI smoke and public-safety verification around that aggregate.

## Findings

### Blockers

- None. The suite shape is maintainable enough to continue feature work, but future Datadog and CLI slices will get slower and riskier without compaction support.

### Important Gaps

- `test/cli_test.rb` repeats subprocess setup, temporary file layout, manifest generation, reviewed provenance injection, stale report setup, and JSON parsing. Extracting shared helpers would reduce noise without removing process-level coverage.
- `test/cli_test.rb` and `test/rules_ctl_test.rb` overlap around onboarding summary, handoff review, handoff validation, and state command error rendering. Keep both styles, but assign clearer ownership before adding more command tests.
- `test/datadog_apply_test.rb` is a single high-value but oversized characterization suite. It is difficult to isolate failures by behavior because applier planning, payload translation, client state discovery, live safety gates, and retry transport tests share one file.
- Onboarding handoff fixtures are duplicated across `test/onboarding_handoff_test.rb`, `test/rules_ctl_test.rb`, and CLI-style tests. Shared public-safe fixture builders would reduce drift in accepted candidate, reviewed packet, and provenance shapes.
- Datadog fake backend helpers live inside `test/datadog_apply_test.rb`. Moving `FakeDatadogClient` and `FakeResponse` to support files would make later Datadog file splits safer.
- The suite has a clear aggregate path, but the intended verification tiers are implicit. New contributors have to infer when to run a focused file, `test/all_test.rb`, or `scripts/verify.sh`.

## Recommendations

1. Add `test/support/cli_helpers.rb` with helpers for `rules_ctl(*args)`, JSON output parsing, temporary manifest files, reviewed provenance injection, and common generate-then-manifest setup.
2. Pilot those helpers in two or three adjacent `test/cli_test.rb` sections first, preferably manifest-review and onboarding-artifact-index tests. Do not rewrite the whole CLI suite in one PR.
3. Add `test/support/onboarding_fixtures.rb` with public-safe handoff packet, reviewed handoff packet, discovery result, discovery index, and reviewed definition fixtures.
4. Add `test/support/datadog_fakes.rb` with the fake Datadog client and fake response classes currently embedded in `test/datadog_apply_test.rb`.
5. Split `test/datadog_apply_test.rb` by behavior after support extraction, not before. Suggested split: `datadog_plan_test.rb`, `datadog_payload_test.rb`, `datadog_client_state_test.rb`, `datadog_live_safety_test.rb`, and `datadog_retry_test.rb`.
6. Clarify test ownership between CLI suites: keep `test/cli_test.rb` for user-visible process contract and exit codes; keep `test/rules_ctl_test.rb` for stubbed branches and internal command error rendering.
7. Document verification tiers in `AGENTS.md` after the helper extraction starts: focused TDD file, aggregate Ruby suite, public-safety suite, and full `scripts/verify.sh`.

## Accepted Deferrals

- Do not delete overlapping CLI assertions until helper extraction makes the overlap visible and easy to review.
- Do not split `test/datadog_apply_test.rb` in the same slice that changes Datadog production abstractions.
- Do not compact tests by reducing subprocess coverage around live mutation gates, saved review freshness, or public-safety checks.

## Next Useful Slice

Pilot a low-risk test support extraction:

- create `test/support/cli_helpers.rb`
- update a small group of manifest-review or onboarding CLI tests to use it
- verify with `ruby -Ilib test/cli_test.rb`, `ruby -Ilib test/rules_ctl_test.rb`, `ruby -Ilib test/all_test.rb`, `ruby -Ilib test/forbidden_terms_test.rb`, and `./scripts/verify.sh`
