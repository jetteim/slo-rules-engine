# Atomic Coherence-Preserving Simplification

Date: 2026-07-28

Status: complete

## Objective

Review the repository end to end, simplify demonstrated structural and test
duplication, and leave every product requirement and observable behavior
unchanged. This is one feature-free, revertible checkpoint.

## Preservation Boundary

The checkpoint must not change:

- neutral DSL or reliability intent
- provider capability, artifact, or automation contracts
- versioned JSON/YAML schemas or serialized field shapes
- CLI commands, arguments, stdout, stderr, exit status, or written files
- review, freshness, ownership, credential, confirmation, journal, locking,
  exact-plan, resume, or verification gates
- backend request or mutation behavior
- public-safe examples, terminology scan, or documentation use cases

Datadog and Sloth evidence-gated roadmap work is explicitly out of scope.

## Before Evidence

Measured from `f26abf2`:

| Measure | Before |
| --- | ---: |
| Production Ruby lines (`lib` plus executable) | 16,529 |
| Ruby test lines | 13,038 |
| Test files | 54 |
| `bin/rules-ctl` lines | 776 |
| Extracted CLI command modules | 8 |
| Duplicate live-status service-rewrite fixture helpers | 2 |
| Separate CLI module-ownership test files | 2 |
| Full verification | 424 tests, 2,721 assertions, 0 failures, 0 errors |

The earlier housekeeping reviews were useful hypotheses, but their largest
Datadog and command-family recommendations have already been completed. The
remaining demonstrated issues are:

1. Library orchestration still lives in the executable even though command
   families live under `lib/slo_rules_engine/cli`.
2. Two one-purpose tests separately load the executable to verify command
   module ownership.
3. Aggregate model and CLI tests duplicate the same recursive transformation
   from the reviewed checkout manifest to another public-safe service identity.
4. `docs/design.md` describes four architecture layers as three and omits the
   current onboarding, release-bundle, provider-state, exact-plan, and
   live-status boundaries.

## Use-Case Traceability

| Engineering task | Value outcome | Primary components | Executable evidence |
| --- | --- | --- | --- |
| 1. Find candidate SLOs | Reusable telemetry evidence before policy | telemetry CLI, provider lookup adapters, candidate generator | `telemetry_lookup_test`, `telemetry_cli_commands_test`, `cli_test` |
| 2. Build onboarding queue | Ranked, reviewable portfolio handoff | batch discovery, onboarding summary/handoff | `telemetry_batch_discovery_test`, `onboarding_summary_test`, `onboarding_handoff_test`, `telemetry_first_walkthrough_test` |
| 3. Discover with one provider and deliver with another | Evidence portability without query inference | neutral bindings, provider registry/generators | `provider_bindings_test`, `providers_test`, `reality_check_test` |
| 4. Generate provider bundle | Deterministic provider artifacts and review report | manifest CLI, providers, manifest schema/review queue | `cli_test`, `manifest_schema_test`, `manifest_review_queue_test`, provider tests |
| 5. Package reviewed release | Content-addressed reviewed release boundary | release-bundle builder/schema/status | `release_bundle_test`, `release_bundle_cli_test` |
| 6. Understand drift | Reviewed desired versus observed state | state CLI, Datadog and file appliers, provider-state values | `apply_test`, `datadog_applier_state_test`, `provider_state_contract_test`, `cli_test` |
| 7. Inventory managed state | Adoption and ownership evidence | import paths, state readers, managed-file importer | `datadog_client_state_test`, `datadog_state_reader_test`, `apply_test`, `cli_test` |
| 8. Create operation journal | Durable deterministic execution intent | journal CLI, journal builder/evaluator/store | `provider_state_journal_test`, `provider_state_journal_cli_test` |
| 9. Approve and execute exact plan | Reviewed immutable file execution | plan CLI, approved plan, exact executor | `provider_state_approved_plan_test`, `provider_state_exact_plan_cli_test` |
| 10. Apply approved multi-target release | Complete preflight and immutable successor | bundle CLI/applier, exact executor | `release_bundle_apply_test`, `release_bundle_apply_cli_test` |
| 11. Apply reviewed state | Gated mutation with durable results | state CLI, appliers, journaled executor/verifiers | `cli_test`, `rules_ctl_test`, manifest/Datadog execution tests |
| 12. Remove managed state | Ownership-gated deletion and absence proof | state CLI, appliers, journaled executor/verifiers | `cli_test`, `rules_ctl_test`, `apply_test`, execution tests |
| 13. Verify telemetry | Binding evidence before adoption | telemetry CLI, reality check, lookup adapters | `reality_check_test`, `telemetry_lookup_test`, `cli_test` |
| 14. Generate alert routes | Contextual route intent without secrets | catalog CLI, notification-router integration | `providers_test`, `cli_test` |
| 15. Validate Datadog sandbox | Public-safe read and temporary lifecycle evidence | sandbox command/client | `datadog_sandbox_smoke_test`, request/state tests |
| 16. Inspect live SLO status | Current objective, budget, burn, freshness, and coverage | status CLI, Prometheus reader, aggregate resolver/reader | `live_status_test`, `live_status_aggregate_test`, `live_status_cli_test` |

`test/use_cases_documentation_test.rb` additionally requires every documented
use case to name concrete output and an intent or safety boundary.

## Contract And NFR Traceability

| Contract or constraint | Owning boundary | Preservation evidence |
| --- | --- | --- |
| Provider manifest schema | providers and `ManifestSchemaValidator` | `manifest_schema_test`, provider tests |
| `provider-state/v1` | provider-state value model | `provider_state_contract_test` |
| `provider-operation-journal/v1` | journal model/builder/evaluator | journal and transition tests |
| `approved-provider-plan/v1` | approved-plan loader/store/executor | approved-plan and exact-plan tests |
| `release-bundle/v1` | release-bundle schema/builder/status | release-bundle tests |
| `bundle-target-execution/v1` | multi-target bundle apply | release-bundle apply tests |
| `live-slo-status/v1` | per-manifest live reader | live-status model/CLI tests |
| `live-slo-status-aggregate/v1` and portfolio input | aggregate resolver/reader | aggregate model/CLI tests |
| Alertmanager route-intent v1 | Prometheus renderer/schema | Prometheus provider/walkthrough tests |
| Credential exclusion | bundle, portfolio, plans, runtime-only clients | release-bundle, approved-plan, live-status tests |
| Fail-closed mutation | CLI review/confirmation and appliers | CLI, rules-ctl, execution tests |
| Durable and atomic execution evidence | journal stores and exact executor | journal, execution, exact-plan tests |
| Sanitized provider failures | Datadog and live-status readers | Datadog HTTP/execution and live-status tests |
| Public-safe repository | terminology and fixtures | `forbidden_terms_test`, `scripts/verify.sh` |

## Selected Atomic Changes

1. Move `RulesCtl` implementation to `lib/slo_rules_engine/cli.rb`; retain
   `bin/rules-ctl` as a shebang, one require, and one dispatch call.
2. Consolidate CLI module ownership assertions into one architecture test that
   loads the library boundary directly and verifies the thin executable.
3. Move public-safe reviewed-manifest service transformation into
   `ReleaseBundleFixtures` and reuse it in aggregate model and CLI tests.
4. Rewrite the architecture document around current components and flows.
5. Refresh both prior housekeeping reviews, roadmap, use cases, and handoff
   with completion evidence and explicit accepted deferrals.

Existing process-level CLI, in-process error rendering, provider, state,
release, exact-plan, and live-status suites already characterize every changed
boundary. No product behavior lacks coverage, so no new behavioral test is
required before the structural move.

## Accepted Deferrals

- Do not split provider-state journal/execution files solely by line count.
  Their classes are cohesive and their exact/resume semantics are high risk.
- Do not add a shared generic hash accessor across domains; local accessors
  preserve boundary-specific defaults and error behavior.
- Do not merge state command branches until a behavior change demonstrates a
  safe common orchestration contract.
- Do not split stable DSL builders or manifest-review internals without a new
  focused responsibility.

## After Evidence

| Measure | After | Change |
| --- | ---: | ---: |
| Production Ruby lines (`lib` plus executable) | 16,532 | +3 |
| Ruby test lines | 13,047 | +9 |
| Test files | 53 | -1 |
| `bin/rules-ctl` lines | 6 | -770 |
| CLI library orchestration lines | 773 | explicit library boundary |
| Extracted CLI command modules | 8 | unchanged |
| Duplicate live-status service-rewrite fixture helpers | 0 | -2 |
| Consolidated CLI module-ownership test files | 1 | -1 |
| Aggregate Ruby suite | 424 tests, 2,766 assertions | +45 assertions |

The production-line increase is the explicit thin bootstrap and library
boundary, not new product behavior. The test-line increase adds broader
architecture ownership assertions while consolidating two files. The
executable no longer contains orchestration.

## Verification Evidence

- Focused CLI architecture: 2 tests, 65 assertions, 0 failures, 0 errors.
- In-process command/error rendering: 14 tests, 67 assertions, 0 failures, 0
  errors.
- Process-level CLI: 55 tests, 280 assertions, 0 failures, 0 errors.
- Aggregate live-status model and CLI: 12 tests, 91 assertions, 0 failures, 0
  errors.
- Aggregate Ruby suite: 424 tests, 2,766 assertions, 0 failures, 0 errors.
- Full repository verification: `./scripts/verify.sh` exited 0 with
  `verification ok`, 424 tests, 2,766 assertions, 0 failures, and 0 errors at
  `2026-07-28T08:27:57Z`.

The focused run caught and corrected a missing executable load guard before the
aggregate run. The final bootstrap retains the prior behavior: loading the
executable defines `RulesCtl` without dispatching, while direct execution
dispatches `ARGV`.

## Outcome

- All 16 engineering use cases and all versioned/safety boundaries retain
  executable evidence.
- No command, schema, artifact, provider read/write, or refusal behavior
  changed.
- CLI orchestration now lives in the library layer and the executable is a
  stable six-line bootstrap.
- Test duplication is lower without reducing process-level or safety coverage.
- The current architecture and dependency rules are documented.
- High-risk semantic file splits remain explicitly deferred.
