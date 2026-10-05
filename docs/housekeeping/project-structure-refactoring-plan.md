# Project Structure Refactoring Plan

Original audit: 2026-08-15. Maintainer review: 2026-09-05.

Status: housekeeping first; HK-01, HK-03, and HK-04 complete; HK-02 implemented,
maintainer navigation feedback pending. HK-05 is the next code task.
STR-0 completed; STR-1 completed; STR-3 partially implemented.

Baseline commit: `6dc0ffb`

## Start Here: Make The Project Understandable Again

Reader: the repository maintainer who needs to understand a change before
approving it. This is the active task queue, not another feature roadmap.
The STR packets below retain their technical acceptance and preservation gates.
HK tasks are smaller execution slices of that work or newly discovered gaps;
they do not create a competing refactoring program.

**Recommendation:** pause additional Agent command coverage, MCP/skill work,
and provider features while the first housekeeping tranche is completed.
Keep existing behavior supported. Do not rewrite the engine or split files just
to make them shorter. The immediate problem is too many places to consult and
too little evidence that cleanup is reducing that burden.

### Current Audit Evidence

The [2026-10-05 abstraction audit](abstraction-layer-review.md) separates useful
boundaries from duplication, leftover helpers, reversed dependencies, and
checker limitations. The [September audit](archive/housekeeping-audit-2026-09-05.md)
is historical; corrected defects and verification are recorded in the tasks.

### Ordered Housekeeping Queue

This table owns current execution order. HK tasks are implementation slices;
STR packets below own structural preservation and dependency-removal gates.
Feature scope lives in the Agent roadmap and implementation history, rather
than a second active queue.

HK-01, HK-03, and HK-04 are complete. HK-02 has implemented documentation with
the maintainer navigation check pending; HK-05–HK-08 remain open.
Sizes indicate review scope, not time estimates:
S = one narrow checkpoint; M = several explicitly separated checkpoints.
One task/checkpoint at a time. Each code checkpoint runs its focused tests,
`scripts/structure-report --check`, `git diff --check`, and full verification.
Do not update snapshot hashes merely to make a check pass: explain the exact
contract change, or show that the old contract remains identical.

| Order | Task | Size | Existing packet / prerequisite |
| --- | --- | --- | --- |
| 1 | HK-01: Make “all tests” actually include all tests (complete) | S | early test-discovery part of STR-7; no domain dependency |
| 2 | HK-03: Close candidate output-policy gaps (complete) | S | AICLI-F3/F4 safety repair; after HK-01 |
| 3 | HK-02: Give the maintainer one map and one current queue (navigation check pending) | M | documentation; after HK-01 and HK-03 |
| 4 | HK-04: Give artifact identity and credential policy one owner (complete) | M | STR-1; after HK-01 and HK-03 |
| 5 | HK-05: Finish command declarations without enabling commands | M | bounded STR-3 work; after HK-02 |
| 6 | HK-06: Make fitness checks match their advertised scope | S | STR-0 follow-up; before dependency moves in HK-07/08 |
| 7 | HK-07: Let Sloth evidence own evidence preflight | M | STR-2; after HK-04 and HK-06 |
| 8 | HK-08: Separate journal storage from execution policy | M | STR-4; after HK-04 and HK-06 |

### HK-01: Make “All Tests” Actually Include All Tests

**Status (2026-09-09):** implemented. The aggregate recursively discovers every
`test/**/*_test.rb` suite; Ruby `require` preserves transitive loading exactly
once. `test/test_discovery_test.rb` compares actual loaded suites and named test
identities and proves discovery of a temporary nested, unregistered suite.
There are no excluded suites; only the aggregate excludes itself from recursion.

**Verification evidence (2026-09-09, local file-backed repository):**
`./scripts/verify.sh` passed 551 tests / 7,448 assertions, structure checks and
CLI smokes. Each previously omitted suite passed independently. The two new
discovery tests passed, including the temporary-suite probe. Loaded suite paths
and named test identities are captured in
`/tmp/slo-hk01-20260909-discovery.json`; full output is in
`/tmp/slo-hk01-20260909-verify.log`. No live provider was contacted. Rollback is
limited to the runner and discovery test; production code is unchanged.

**Work:** repair `test/all_test.rb` discovery and add a regression check that
compares eligible test files with loaded suites, allowing only named exclusions
with reasons. Preserve intentional transitive Datadog test loading. Keep this
separate from splitting `cli_test.rb` or changing application code.

**Acceptance:** all three omitted suites run through `scripts/verify.sh`; a
new unregistered test causes a failure or is automatically included exactly
once. Record loaded files and named test identities, not just assertion totals.
The present combined count is expected to start at 549 tests / 7,440 assertions
before adding the discovery regression; verify it rather than hardcoding it.

**Verification:** run individual omitted suites, the aggregate, and full verify;
use a temporary unregistered test to prove the discovery check catches it.
**Rollback:** revert test-runner/check changes only; no runtime behavior changes.

### HK-02: Give The Maintainer One Map And One Current Queue

**Implementation (2026-10-05):** [the maintainer guide](../maintainer-guide.md)
now explains the workflow, saved objects, source/test ownership, a shared
Human/Agent generation path, legacy handlers, and where to investigate refused
apply. README routes maintainers to it before operational reference. AGENTS.md
now contains operating rules, evidence gates, and links; its prior 974-line
handoff is preserved [verbatim](archive/agents-2026-10-05.md). September audit
findings are archived above. The architecture reference now distinguishes
migrated and legacy command paths and reflects implemented Sloth evidence support.
The [current abstraction audit](abstraction-layer-review.md) records independently
checked redundancy and dependency inconsistencies.

**Verification evidence (2026-10-05 UTC, local repository at `611d450`):**
`./scripts/verify.sh` passed 558 tests / 7,550 assertions, zero failures,
errors, or skips, architecture checks, and CLI smokes. Focused documentation
tests passed 13 tests / 653 assertions; the offline Prometheus walkthrough
passed one test / 47 assertions. At 14:57 UTC, a local check resolved all 160
links in the 13 changed/new Markdown files and proved the AGENTS archive
byte-identical to its original. The guide's Human/Agent examples both exited
zero and produced identical manifest/review artifacts in temporary confined
output roots. `git diff --check` passed. No backend queries, metric/log/trace
reads, or provider mutation were performed. Production code and contracts are
unchanged. Outputs: `/tmp/slo-hk02-20261005-verify.log`,
`/tmp/slo-hk02-20261005-docs.log`, `/tmp/slo-hk02-20261005-walkthrough.log`,
`/tmp/slo-hk02-20261005-links.json`, and
`/tmp/slo-hk02-20261005-guide-examples.json`. Rollback: revert this documentation
checkpoint independently of HK-01/03, retaining historical evidence.

**Human evidence:** comprehension remains unverified. Ask the maintainer to use
the guide to (1) trace a generated Prometheus YAML file to its definition,
(2) find the shared generation handler and its tests, and (3) locate the gates
behind an apply refusal. Record their result before closing this acceptance
item or resuming feature expansion. HK-04's policy extraction is complete;
HK-05 is the next code task.

**Work:** first add a short maintainer explanation, linked prominently from
README: intent → reviewed artifacts → plan → journaled execution → verification;
live status is a read-only observation path, not execution. Map these concepts
to actual files, public facades, focused tests, and one file-backed walkthrough.
Show one Human and Agent command reaching the same application command, and
explicitly identify legacy commands that have not moved to that seam.
Second, trim `AGENTS.md` to operating rules, evidence gates, and links; move
historical checkpoint detail to an archive. Keep current execution order here,
feature scope in the Agent roadmap, contracts in their existing references,
and procedures in use cases/walkthroughs. Remove repeated progress inventories.

**Acceptance:** the maintainer can trace a generated file to its definition,
locate the shared command handler and its tests, and explain why apply is
refused without reading the historical roadmap. Aim for a map readable in ten
minutes and `AGENTS.md` under 200 lines; these are readability targets, not CI
line-count laws. Ask the maintainer to try the three navigation tasks; until
then record human comprehension as unverified. Preserve old links/anchors or
provide explicit replacement links; adapt prose-pinning tests without dropping
contract coverage.

**Verification:** follow every code/test link and the existing offline
Prometheus walkthrough; run documentation tests. **Rollback:** revert each
documentation move independently; preserve the archive and original content.

### HK-03: Close Candidate Output-Policy Gaps

**Status (2026-09-09):** complete ahead of HK-02 because the real Agent CLI
reproduced the arbitrary-object calculation-basis leak. Supported enum values
are preserved; other values produce `candidate_text_quarantined` fingerprints
and fall back to the traffic recommendation or `observations`. Candidate input,
output, and nested output fields now have explicit allowlists. Numeric evidence
must also be representable as finite floats. Human generation semantics remain
unchanged; supported Human/Agent results and intentional text differences have
process-CLI regression coverage. The command's registry/introspection metadata
now declares `candidate_output_allowlist`, `calculation_basis_enum`, and
`explicit_candidate_shape_with_quarantine`; request schemas and artifact IDs
are unchanged. Reversing exactly those candidate metadata edits reproduces
the prior registry digest; the catalog digest and all other fields are unchanged.
The application file retains the same two commands and support module; the
new lines enforce this existing presentation boundary rather than adding a
new command or generic response framework.

**Verification evidence (2026-09-09 UTC, local file-backed repository):**
`./scripts/verify.sh` passed 558 tests / 7,550 assertions, with no failures,
errors, or skips, plus architecture checks and CLI smokes. Candidate and
introspection suites passed 19 tests / 557 assertions. Process-CLI tests cover
nested values, controls, oversized strings/arrays/integers, malformed core
fields, numeric limits, both supported basis values, traffic-derived fallback,
and intentional Human/Agent presentation differences. Existing confinement,
handoff zero-I/O, Human onboarding, and public-safety suites remain included.
Evidence: `/tmp/slo-hk03-20260909-focused.log`,
`/tmp/slo-hk03-20260909-verify.log`, and the exact registry migration proof in
`/tmp/slo-hk03-20260909-contract-migration.log`. No live provider or telemetry
queries were performed. Rollback: revert this isolated safety checkpoint and
its metadata digest together; if reverted, mark HK-03 open and retain the
Agent expansion pause.

**Work:** characterize every field copied from telemetry into Agent candidate
results, including `calculation_basis`, IDs, numeric fields, and optional text.
Define an explicit allowed output shape instead of assuming selected input
fields cover every generator output. Keep generation semantics separate from
Agent presentation; document intentional Human/Agent differences rather than
silently replacing reviewed meaning. No new Agent commands or generic response
framework in this task.

**Acceptance:** the canary object above cannot pass as a calculation basis;
unsupported types/text produce stable refusal or declared quarantine. Test
nested values, controls, oversize strings and arrays, and supported enum values
through the real Agent CLI. Preserve valid Human behavior and confined/zero-I/O
gates. Update both interface contracts, parity tests, introspection and usage
for the intentional safety correction.

**Verification:** Agent onboarding/adversarial tests, Human onboarding tests,
registry/introspection and full verify. **Rollback:** isolated safety-fix commit;
if reverted, mark the defect open and keep command expansion paused.

### HK-04: Give Artifact Identity And Credential Policy One Owner

**Status:** complete in two independently revertible checkpoints.

**Migration implementation (2026-10-05):** `ArtifactIntegrity::Fingerprint` and
`ArtifactIntegrity::CredentialScanner` own the characterized policies in one
independently loadable file. Existing state/release constants, manifest-review
helpers, and onboarding helpers delegate. Onboarding keeps its `sha256:` prefix,
serialization-error text fallback, and `fetch` semantics. Bundle identity assembly
and exact findings remain in their owners. No command is enabled or changed.

Sloth evidence/MCP and live aggregation now use the neutral owner directly.
The exact six migrated allowlist entries (nine occurrences) are removed; current
configured debt falls from 15 to 6 occurrences. Remaining release/status/preflight
edges retain their later packets. The new neutral boundary has a zero-debt rule
and an isolated negative fixture. There are 101 production files and still 64
root requires. Contract snapshots and all pre-extraction goldens are unchanged;
the production-file count assertion changes only for the named new owner.

**Migration verification (2026-10-05, 21:42–21:44 UTC, local repository):**
focused integrity, boundary, Agent onboarding, Sloth evidence/MCP, and aggregate
status suites passed 51 tests / 543 assertions. `./scripts/verify.sh` passed
567 tests / 7,672 assertions, zero failures/errors/skips, architecture checks,
and CLI smokes. The aggregate includes both complete offline usability
walkthroughs. All pre-extraction golden fingerprints/IDs remain equal.
The structure report shows 101 owned production files, 64 root requires,
40 commands, 21 artifact schema IDs, 120 command schema references, and 19 use
cases. The exact architecture contract snapshot and current contract inventory
compare unchanged; no digest was refreshed. Debt decreases from 15 to 6
configured forbidden-reference occurrences by removing only the nine migrated
release-utility references. No backend queries, metric/log/trace reads, or
provider mutations occurred. Outputs:
`/tmp/slo-hk04-20261005-migration-focused.log`,
`/tmp/slo-hk04-20261005-migration-verify.log`,
`/tmp/slo-hk04-20261005-after-structure.json`, and
`/tmp/slo-hk04-20261005-parity.json`. Rollback: revert the migration checkpoint
with its boundary/count changes; retain the characterization checkpoint and
its original golden fixture. Later dependency packets remain open.
Final documentation/public-safety checks passed 13 tests / 653 assertions after
updating task status; `git diff --check` passed. Output:
`/tmp/slo-hk04-20261005-documentation.log`.

**Characterization checkpoint (2026-10-05, baseline `18d0879`):**
`test/artifact_integrity_compatibility_test.rb` locks canonical JSON bytes,
symbol/string collisions, array order, input immutability, exact credential-key
paths, text-vs-JSON hashing, and onboarding's prefix/error fallback. A Hash
subclass probe demonstrates onboarding's `fetch` semantics versus the other
helpers' bracket reads; preserve that distinction. Saved pre-extraction goldens
cover state/plan/journal/approval/bundle/evidence/comparison identities and all
three providers' generated manifest/review content. Identity-only synthetic
inputs do not claim full artifact schema validity.

**Characterization evidence (2026-10-05, 21:38 UTC, local repository):**
focused tests passed 7 tests / 114 assertions. `./scripts/verify.sh` passed
565 tests / 7,664 assertions, architecture checks, and CLI smokes. Offline
onboarding and Prometheus managed-file walkthroughs passed 2 tests / 69
assertions, proving those complete documented flows remain usable. No backend,
metric/log/trace reads or provider mutations occurred. Outputs:
`/tmp/slo-hk04-20261005-characterization.log`,
`/tmp/slo-hk04-20261005-characterization-verify.log`,
`/tmp/slo-hk04-20261005-usability.log`, and
`/tmp/slo-hk04-20261005-before-structure.json`. Production code is unchanged.
Rollback: revert this test/fixture checkpoint independently of the migration.

**Work:** execute STR-1 in two checkpoints: golden-vector characterization,
then shared owner plus compatibility delegates and caller migration. Include
`OnboardingCommandSupport#fingerprint` and manifest-review hashing in the inventory.
Compare implementations before consolidation: text hashing, JSON hashing,
symbol values, duplicate string/symbol keys, error fallback, and finding paths
are not assumed interchangeable.

**Acceptance:** one owner for each proven identical policy; old public helpers
delegate; supported artifact IDs and credential findings remain byte-identical.
Preserve demonstrated differences explicitly instead of normalizing them away.
Remove the exact migrated release-utility debt entries and record before/after.
Do not extract unrelated `fetch_value` helpers or a generic artifact framework.

**Verification:** STR-1 suites plus Agent onboarding fingerprint/quarantine
tests and golden artifacts. **Rollback:** keep existing constants/load paths;
revert migration independently from characterization.

### HK-05: Finish Command Declarations Without Enabling Commands

**In progress:** Sloth evidence/MCP now owns three explicit declarations in
`cli/command_contracts/sloth.rb`. Corresponding legacy usage/example/assembly
entries are removed. The pre-migration registry, compact catalog, full Agent
catalog, and all 40 descriptions are captured at `090a070`; persistent
preservation hashes exclude only the authoring-source label. Reversing the
three `inferred` → `explicit` labels reproduces every original wire field.
Resolved schemas, including known optional-field limitations, are unchanged;
thirteen application mappings remain enabled. The registry digest changes only
for those source labels; the compact catalog digest is unchanged.

**Family checkpoints (local repository, 2026-10-05 UTC):**

| Family | Explicit declarations after checkpoint | Full verification | Evidence prefix in `/tmp/` |
| --- | ---: | --- | --- |
| Sloth evidence/MCP | 23 / 40 | 569 tests / 7,724 assertions | `slo-hk05-sloth-` |
| Live status | 24 / 40 | 569 tests / 7,726 assertions | `slo-hk05-status-` |
| Agent introspection | 26 / 40 | 569 tests / 7,730 assertions | `slo-hk05-introspection-` |
| Release bundle | 31 / 40 | 569 tests / 7,740 assertions | `slo-hk05-release_bundle-` |
| Journal | 33 / 40 | 569 tests / 7,744 assertions | `slo-hk05-journal-` |

Sloth checkpoint verification at 21:56–21:58 UTC: focused registry,
introspection, invocation, preservation and fitness suites passed 32 tests /
3,337 assertions. Full `./scripts/verify.sh`, `scripts/structure-report --check`,
and `git diff --check` passed. The proof JSON records the exact source-label
delta and registry digest migration. Logs are `PREFIXfocused.log`,
`PREFIXverify.log`, and `PREFIXproof.json`. No live provider calls, mutations,
or metric/log/trace reads occurred. Rollback: revert the family checkpoint,
its registry digest, and its named production-file count change together;
retain baseline preservation goldens. HK-05 remains open for other families
and the separate orchestration checkpoint.

Live status checkpoint verified 2026-10-05 22:00:45 UTC: 32 focused tests / 3,339 assertions; full verification, wire comparison, and structure checks passed. Its table prefix identifies the focused/full/proof outputs. Registry changes remain limited to authoring provenance; application mappings stay at thirteen. No live provider or telemetry reads/writes occurred.

Agent introspection checkpoint verified 2026-10-05 22:02:39 UTC: 32 focused tests / 3,343 assertions; full verification, wire comparison, and structure checks passed. Its table prefix identifies the focused/full/proof outputs. Registry changes remain limited to authoring provenance; application mappings stay at thirteen. No live provider or telemetry reads/writes occurred.

Release bundle checkpoint verified 2026-10-05 22:04:13 UTC: 32 focused tests / 3,353 assertions; full verification, wire comparison, and structure checks passed. Its table prefix identifies the focused/full/proof outputs. Registry changes remain limited to authoring provenance; application mappings stay at thirteen. No live provider or telemetry reads/writes occurred.

Journal checkpoint verified 2026-10-05 22:05:18 UTC: 32 focused tests / 3,357 assertions; full verification, wire comparison, and structure checks passed. Its table prefix identifies the focused/full/proof outputs. Registry changes remain limited to authoring provenance; application mappings stay at thirteen. No live provider or telemetry reads/writes occurred.

**Work:** finish the metadata half of STR-3 one remaining family at a time;
remove each migrated family's legacy usage/examples/schema-inference source
in the same checkpoint. Keep typed-handler extraction a separate checkpoint
only where there is demonstrated duplicated orchestration. Record one worked
example showing all files needed to maintain a command. The current abstraction
audit identifies three repository-unused RulesCtl helpers and three matching
provider-validation loops; remove or consolidate them in isolated preservation
checkpoints after checking public-library compatibility. Characterize corrections
to inferred optional/conditional schemas separately from structural moves.

**Acceptance:** all 40 commands have one explicit declaration owner; existing
registry/catalog output and resolved schemas compare equal; command coverage
stays at thirteen executable Agent commands. No handler discovery framework,
new adapter, or newly enabled side effect. Docs link to runtime introspection
for exhaustive metadata rather than reproducing it in multiple inventories.

**Verification:** compare complete before/after registry, catalog and describe
outputs; run Human/Agent parity and unsupported-command refusal tests.
**Rollback:** one family per revertible commit behind the existing registry.

### HK-06: Make Fitness Checks Match Their Advertised Scope

**Work:** reconcile boundary declarations with the actual regex checks and
label their limitations. Reconcile Datadog state-file ownership with the declared
provider-translation restrictions. Add negative fixtures for missing rule coverage and
representative forbidden edges; do not build a general Ruby static analyzer.
Align removal ownership for shared policy with STR-1, evidence preflight with
STR-2, actual runtime status coordination with STR-5, and approved plans with
STR-4. Hook use-case evidence into HK-01's suite inclusion check.

**Acceptance:** every declared boundary restriction has a test or an explicit
documented limitation; an allowed-dependency declaration cannot imply coverage
that does not exist. No widened allowlist, removed debt finding, or snapshot
refresh without the matching code/evidence change.

**Verification:** architecture negative fixtures, deterministic report, suite
inclusion, and unchanged runtime contract snapshots. **Rollback:** checker and
policy edits only; keep recorded debt evidence for the restored policy.

### HK-07: Let Sloth Evidence Own Evidence Preflight

**Work:** execute STR-2 with two reviewable checkpoints: move existing evidence
collaborators behind the old require path, then move exact-source preflight
out of `LiveStatus::SlothReader`. Update release/status/MCP callers together.

**Acceptance:** callers can validate evidence without reaching into a live
reader. Remove preflight-only dependency edges; do not claim all runtime-status
dependencies are removed. No external generator execution or schema changes.

**Verification:** STR-2 suites, including the newly included Sloth live-status
suite; preserve fail-before-client/read order and exact artifacts/findings.
**Rollback:** stable evidence facade and independently revertible moves.

### HK-08: Separate Journal Storage From Execution Policy

**Work:** execute STR-4 as distinct checkpoints for existing journal classes,
approved-plan status dependency inversion, and executor/result responsibilities.
Keep the current storage format and constructor compatibility; do not redesign
the state machine while moving it.

**Acceptance:** a reader can find transition rules, atomic storage, retry
eligibility, and result construction separately; provider state no longer
defaults internally to release orchestration. Exact plans, locks, attempts,
resume behavior and final verification remain unchanged.

**Verification:** STR-4 suites, failure injection, replay/resume and file-backed
release apply/verify. **Rollback:** one responsibility per checkpoint behind
the existing public constants and load paths.

### Stop Conditions And Later Work

Review the first tranche after HK-01 through HK-06. Resume feature expansion
only after suite discovery is trustworthy, the known safety defect is closed,
the maintainer has tried the code map, and repeated policy/metadata has actually
been removed. The maintainer can then choose the next feature or HK-07/08;
there is no requirement to fund an indefinite cleanup program.

Keep STR-5 release phases, STR-6 MCP/applier internals, and the remaining STR-7
CLI test split/composition-root work queued behind their existing dependency
gates. The early HK-01 test-discovery repair does not authorize early root-loader
rewrites. Stable DSL and Datadog freeze zones remain unchanged. Live Datadog
and tagged Sloth MCP verification remain deferred; this review made no backend
calls and did not establish any new live-provider evidence.

The original audit created tasks and adjusted sequencing only. HK-01 and
HK-03 now have implementation evidence above; maintainer comprehension remains
unverified until HK-02's navigation exercise. The historical audit below explains the preserved STR design; where
its feature-first sequence differs, this current queue takes precedence.

## Objective

Keep feature growth from turning the rules engine into a network of implicit
dependencies and oversized workflow objects. The work is repository-wide in
analysis, but execution is split into eight behavior-preserving packets. Each
packet is one independently revertible checkpoint with focused
characterization, the aggregate suite, public-safety checks, and a full
verification run.

This plan does not optimize for fewer lines or more abstractions. It optimizes
for explicit dependency direction, one owner per contract, stable public
facades, small reasons to change, and tests that identify the failed boundary.

## Preservation Boundary

Every packet must preserve:

- provider-independent reliability intent and the Ruby DSL
- all 19 engineering use cases and their documented stdout, files, provider reads and writes,
  and refusal behavior
- Human CLI and Agent CLI mappings, command IDs and versions, exit status,
  stdout/stderr rules, and usage
- versioned schemas, serialized field shapes, fingerprints, IDs, finding and
  refusal codes, and content-addressed lineage
- provider capabilities, generated Datadog, Prometheus Stack, and Sloth
  artifacts, and notification route intent
- review, provenance, freshness, ownership, confirmation, exact-plan, locking,
  journal, resume, verification, and credential-exclusion gates
- current backend request semantics; no live Datadog or Sloth mutation is added
- public-safe fixtures, terminology, and repository history

No packet may combine a structural move with an unrelated feature. A feature
may supply the extraction seam, but characterization must prove the old and new
entry points are equivalent before the feature is enabled.

## Audit Method

The audit used the clean `main` tree after runtime Agent introspection. Evidence
was gathered from file and method counts, literal composition dependencies,
cross-boundary constant references, current C4/component documentation, test
topology, existing housekeeping decisions, the 40-command registry, and the
full verification result.

The measurements are indicators, not automatic split rules. A large cohesive
file can stay intact; a smaller file with reverse dependencies or parallel
sources of truth takes priority.

## Baseline Evidence

| Measure | Current | Previous atomic review | Change |
| --- | ---: | ---: | ---: |
| Production Ruby lines (`lib` plus executable) | 21,467 | 16,532 | +4,935 (+29.9%) |
| Ruby test lines | 16,092 | 13,047 | +3,045 (+23.3%) |
| Production Ruby/executable files | 82 | not recorded | current baseline |
| Ruby test files | 71 | 53 | +18 |
| Registered commands | 40 | not applicable | Human/Agent contract baseline |
| Focused CLI command modules | 11 | 8 | +3 |
| Root composition dependencies | 63 direct requires | not recorded | flat load graph |
| Unique versioned schema strings in production | 20 | not recorded | preservation inventory |
| Full verification | 487 tests, 6,423 assertions | 424 tests, 2,766 assertions | green |

The audit baseline contained 20 unique literal versioned artifact schema IDs.
The first two AICLI-F2/STR-3 slices have since moved the guarded inventory to 94
production/executable files, 64 root composition dependencies, and 21 unique
versioned schema strings. The table remains the pre-refactoring audit baseline;
the architecture fitness configuration and completion evidence below track the
current inventory.

Largest production concentration:

| File | Lines | Definitions | Current responsibility evidence |
| --- | ---: | ---: | --- |
| `lib/slo_rules_engine/sloth/downstream_evidence.rb` | 1,167 | 60 methods, 5 main collaborators | parsing support, build, schema validation, freshness/status |
| `lib/slo_rules_engine/provider_state/journal_execution.rb` | 884 | 41 methods, 5 main collaborators | transition, storage, result construction, execute/resume |
| `lib/slo_rules_engine/release_bundle/verifier.rb` | 828 | 28 methods | lineage preflight, downstream preflight, resource verification, successor build |
| `lib/slo_rules_engine/sloth/mcp/comparison.rb` | 745 | 35 methods | runtime contract, pagination, collection, semantic comparison, report build |
| `lib/slo_rules_engine/cli.rb` | 745 | 28 methods | remaining state/generation commands plus shared CLI services/rendering |
| `lib/slo_rules_engine/appliers/manifest_bundle.rb` | 684 | 38 methods | file planning/import/prune plus exact execution/resume |
| `lib/slo_rules_engine/cli/command_registry.rb` | 572 | 24 methods | definition type, registry, usages, examples, and 40 command declarations |

Largest test concentration is `test/cli_test.rb` at 1,740 lines. It remains a
valuable process contract, but one class covers provider generation, review,
state, telemetry, onboarding, and reporting. The current architecture test
manually lists only 9 of 11 command-family modules, so its ownership inventory
can drift even while handler existence remains covered elsewhere.

## Findings

### P0: Dependency Direction Is Documented But Not Enforced

`lib/slo_rules_engine.rb` loads 63 implementation files directly. Most
implementation files rely on that global load order instead of declaring a
bounded-context entry point. Static `require_relative` inspection therefore
shows a flat graph while constant references reveal reverse and cyclic domain
dependencies:

- `ReleaseBundle -> LiveStatus`: bundle building and verification call the
  Sloth live-status reader for downstream-evidence preflight.
- `ProviderState -> ReleaseBundle`: approved-plan construction defaults to the
  release-bundle status evaluator.
- `ReleaseBundle -> ProviderState`: planning, application, and verification use
  provider plans, journals, values, and results.
- `LiveStatus -> ReleaseBundle`: aggregate input resolution uses bundle status,
  fingerprinting, and credential scanning.
- `Sloth -> ReleaseBundle` and `Sloth -> LiveStatus`: evidence and MCP code use
  release utilities and the live-status preflight path.

These dependencies currently work because the root loads everything. They make
isolated loading, substitution, and boundary enforcement difficult and allow a
new feature to deepen cycles unnoticed.

### P0: Shared Artifact Policy Has Multiple Owners

Canonical JSON hashing appears in `ProviderState::Fingerprint`,
`ReleaseBundle::Fingerprint`, and manifest review code. The exact
`CredentialScanner` key policy is duplicated in provider state and release
bundle code, while Sloth and live status reach into the release-bundle copy.

This is demonstrated duplication with a safety impact. Fingerprint or
credential-key drift could invalidate lineage or allow a credential-like field
through one artifact family. It is a better extraction candidate than a generic
hash accessor because its semantics are already identical and cross-cutting.

### P0: Command Contract Metadata Is Parallel

The command contract is canonical at runtime, but its source is spread across
`HUMAN_USAGE`, `AGENT_ARGUMENT_EXAMPLES`, the `build` declaration list,
`CommandSchemas` inference, test inventory, and documentation inventory.
Validation catches missing entries, but adding or changing one command still
requires coordinated edits across parallel structures. Schema inference from
an example is also too weak to be the long-term source for optional forms,
conditional requirements, and safe Agent invocation.

This pressure must be addressed before `agent invoke` expands command
normalization or result contracts.

### P1: Several Files Contain Clear Collaborator Boundaries

The large multi-class provider-state and Sloth evidence files already contain
named collaborators. File-only decomposition can improve ownership without
inventing new public APIs:

- `sloth/downstream_evidence.rb`: `Support`, `Builder`, `SchemaValidator`, and
  `StatusEvaluator`
- `provider_state/journal_execution.rb`: `JournalTransitioner`, `JournalStore`,
  `ResultBuilder`, and `JournaledExecutor`
- `provider_state/operation_journal.rb`: value, builder, and evaluator
- `provider_state/approved_plan.rb`: document, builder, loader, evaluator, and
  store

The public constants and constructor defaults must remain compatible. These
splits happen only with the relevant focused suites green before the move.

### P1: Workflow Objects Combine Policy Phases

`release_bundle/verifier.rb`, `sloth/mcp/comparison.rb`, and
`appliers/manifest_bundle.rb` are mostly single public facades, but each owns
multiple policy phases. Their extraction seams are phase-oriented, not based on
line count:

- preflight and lineage validation
- evidence or state collection
- per-target/resource semantic evaluation
- successor/report construction
- execution and replay

The facades should remain stable while private collaborators take one phase at
a time.

### P1: Interface Parsing And Application Work Are Still Coupled

The focused CLI modules improved ownership, but methods still combine
`OptionParser`, file/provider construction, orchestration, JSON rendering, and
`exit`. `lib/slo_rules_engine/cli.rb` retains generation, manifest review,
apply, diff, import, prune, shared review gates, and error rendering. Reusing
these methods for Agent JSON by reconstructing `argv` would cement interface
syntax into the application boundary.

Human and Agent adapters need to normalize into typed application commands
whose return values do not print or exit. This must be introduced vertically,
not by rewriting all 40 commands at once.

### P2: Test Ownership Can Be Easier To Navigate

Domain and Datadog tests are already well split. Remaining pressure is
concentrated in `test/cli_test.rb` and manual architecture inventories. Process
coverage must be retained, but it can be grouped by command family with an
aggregate compatibility entry point, following the existing Datadog pattern.

## Target Dependency Model

```text
Human CLI adapter     Agent CLI adapter     future MCP adapter
          \                |                /
             application command boundary
                         |
        cross-domain workflow coordinators and ports
          /          /          |          \
 onboarding   provider state   release   live/runtime evidence
          \          |          |          /
             provider artifacts and neutral intent
                         |
       artifact identity/safety + standard library adapters
```

Dependency rules:

1. Neutral intent depends only on standard library value support.
2. Artifact identity and credential-key policy have one provider-neutral owner.
3. Provider generators depend on neutral intent, not release or CLI code.
4. Provider state consumes validated provider artifacts and artifact support;
   it does not default to a release-bundle implementation.
5. Sloth downstream evidence owns Sloth evidence preflight. Live status,
   release workflows, and MCP comparison consume that facade instead of calling
   each other for preflight.
6. Release orchestration may depend on provider state and runtime-evidence
   ports. Provider state and evidence code do not depend back on release.
7. Core live-status readers consume reviewed manifests and provider query
   ports. Bundle/portfolio input resolution is an application adapter.
8. Interface adapters parse and render only. Application commands return typed
   results or typed failures and never call `puts`, `warn`, or `exit`.
9. Command metadata, examples, request schemas, skills, and MCP definitions are
   projections from one contract declaration.
10. Existing facades and versioned artifact contracts remain stable during
    internal moves.

## Growth Guardrails

STR-0 makes these rules executable before broad movement starts:

- Record current cross-boundary references in an exact, owned debt allowlist.
  New edges fail CI. Each existing exception names the packet that removes it.
- Generate the command-family ownership check from the registry and module
  declarations; do not maintain another incomplete hand-written inventory.
- Emit a deterministic structural report containing production/test lines,
  file/method concentration, composition dependencies, command count, schema
  inventory, and allowed boundary debt.
- A changed hotspot must not gain a new responsibility. Growth over 10% requires
  a short decision in the packet explaining why the file remains cohesive or
  naming the extraction performed.
- A new command is incomplete unless one declaration yields its Human mapping,
  Agent mapping, explicit request schema, introspection, use-case output, and
  parity evidence.
- No new domain code may depend on `RulesCtl`, `OptionParser`, or interface
  rendering. No new provider code may depend on release or CLI constants.
- Do not introduce a generic validation framework or hash accessor. Extract
  only identical policy with contract tests and preserve boundary-specific
  defaults and findings.

## Delivery Packets

Packet numbers are stable identifiers. The current HK queue above controls
execution priority; STR-3 metadata cleanup need not enable another Agent
command. STR-0 is already complete.
Structural dependency order is STR-1 before STR-2/STR-4, STR-2 and STR-4 before
STR-5/STR-6, and STR-7 composition cleanup last. HK-01 brings only independent
test-discovery repair forward. Only one packet is active at a time.

### STR-0: Architecture Fitness And Preservation Baseline (completed 2026-08-15)

**Intent:** stop structural debt from increasing before moving code.

**Work:** add a deterministic structure report, a boundary map, an exact
current-debt allowlist, architecture tests for forbidden new edges, a complete
registry-derived command-module ownership check, and contract snapshots for 40
commands and the versioned artifact inventory. Split no production behavior.

**Acceptance:** current debt is visible; an added forbidden dependency or
unregistered command module fails; the Human/Agent catalog and all public
schema IDs remain identical; all 19 use cases map to tests.

**Verification:** architecture, registry, documentation, aggregate, forbidden
terms, and `./scripts/verify.sh`.

**Rollback:** revert STR-0 only; runtime behavior is untouched.

**Completion evidence:** `scripts/structure-report` now emits the deterministic
`structure-report/v1` inventory and `scripts/structure-report --check` is part
of full verification. `config/architecture_dependencies.json` assigns all 100
current production/executable files to one boundary and records each current
forbidden reference with its removal packet. `config/architecture_contracts.json`
locks the 40-command registry/catalog digests (including 120 per-command schema
references), 21 current unique literal versioned artifact schema IDs, and
all 19 use-case-to-test mappings. `test/architecture_fitness_test.rb` enforces
those contracts, while `test/cli_architecture_test.rb` derives all 11 command
modules and their registered adapters from the filesystem and registry. No
production file or runtime behavior changed. The original audit's schema count
was corrected from 22 to 20 after filename-qualified duplicate occurrences
were deduplicated.

### STR-1: Shared Artifact Identity And Safety Kernel

**Status:** complete in HK-04; see its verification and preservation evidence.

**Intent:** remove demonstrated duplication and eliminate lower layers reaching
into `ReleaseBundle` for generic artifact policy.

**Work:** introduce one provider-neutral canonical JSON/fingerprint component
and one credential-key scanner. Keep `ProviderState::Fingerprint`,
`ReleaseBundle::Fingerprint`, and both `CredentialScanner` constants as
compatibility delegates until callers migrate. Add golden vectors covering
symbol/string keys, ordering, arrays, text artifacts, and forbidden key paths.

**Acceptance:** every existing fingerprint, bundle ID, plan ID, journal ID,
evidence ID, and credential finding is byte-for-byte unchanged; Sloth and live
status no longer depend on release utilities for these policies; debt edges are
removed from the allowlist.

**Verification:** provider-state, release-bundle, Sloth evidence/MCP,
live-status, public-safety, and full verification.

**Rollback:** compatibility delegates make the packet independently revertible.

### STR-2: Sloth Evidence Boundary And File Decomposition

**Intent:** make downstream-evidence validation the stable lower-level facade
used by release, status, and MCP workflows.

**Work:** split `sloth/downstream_evidence.rb` by its existing collaborators
without renaming public constants. Extract exact manifest/evidence/source
preflight from `LiveStatus::SlothReader` into the downstream-evidence boundary.
Make live status, release builder/verifier, and MCP comparison consume that
preflight result. Keep status querying in live status.

**Acceptance:** evidence JSON, fingerprints, findings, stale-source behavior,
MCP comparison, live status, and bundle verification are unchanged;
`ReleaseBundle -> LiveStatus` is removed for evidence preflight.

**Verification:** Sloth evidence model/CLI, live status, MCP, release builder and
verifier suites, then full verification.

**Rollback:** facade require file preserves the old load path and constants.

### STR-3: Single-Declaration Command Contracts And Application Seam

**Intent:** prevent Agent invocation from duplicating Human parsing semantics or
growing the registry into another monolith.

**Work:** move command declarations into bounded command-family contract files
assembled by `CommandRegistry`. Each declaration owns Human usage, Agent
example, explicit request schema, side effects, I/O, safety, result/error refs,
and MCP metadata. Keep `CommandCatalog` as the separate compact Human-to-Agent
projection. Introduce one typed application-command vertical slice at a time;
Human flags and Agent JSON normalize to it, and rendering remains in adapters.

Start with side-effect-free introspection/validation/reporting. Add local-write,
provider-read, and provider-mutation commands only after AICLI-F3 safety gates
for that class exist. Do not manufacture Human `argv` inside the Agent adapter.

**Acceptance:** every command is authored once; schemas are explicit rather
than inferred only from examples; registry IDs/order and current Human behavior
are compatible; equivalent Human and Agent normalized inputs reach the same
application command; no application command prints or exits.

**Verification:** registry/introspection, Human CLI characterization, Agent
equivalence, no-I/O spies, use-case documentation, and full verification.

**Rollback:** migrate one command family per commit behind the unchanged
registry and RulesCtl facade.

**Current progress (2026-09-05):** the complete catalog, analysis, and
provider-state families; telemetry and onboarding families; plus
generation/review now own Human usage, Agent
examples, and explicit argument schemas in bounded declaration modules. `providers.list`,
`integrations.list`, `recommend-calculation-basis`, `validate`,
`migration-report`, `model-report`, file-backed `diff`, `generate`, and
`manifest-review`, telemetry lookup/discovery, bounded candidates, and confined
handoff review normalize Human flags or Agent JSON into typed application
commands that return values without printing or exiting. Generation/review
and handoff review also enforce confined Agent destinations and zero-I/O
`validate_only`.
Remaining command families still use the compatibility assembly and keep STR-3
open.

### STR-4: Provider-State File Boundaries And Release Inversion

**Intent:** make journal, result, and exact-plan responsibilities navigable
without changing their state machine.

**Work:** split `provider_state/journal_execution.rb`,
`provider_state/operation_journal.rb`, and `provider_state/approved_plan.rb`
along existing class boundaries. Preserve constant names and constructor APIs.
Remove the `ProviderState -> ReleaseBundle` default dependency by injecting the
source-bundle status port at the application composition boundary; keep a
compatibility constructor path while callers migrate.

**Acceptance:** transition matrix, attempts, lock behavior, atomic writes,
resume eligibility, recheck, exact execution, result rollups, approved-plan
identity, and all refusal codes are unchanged; no journal or approved plan
schema changes.

**Verification:** provider-state contract/journal/transition/approved-plan and
exact-plan CLI suites, manifest-bundle execution, release apply/verify, then
full verification.

**Rollback:** file entry points retain old require paths; each class split is a
separate commit within the packet.

### STR-5: Release Workflow Phase Collaborators

**Intent:** reduce change collision inside bundle verification and application
while retaining one public release facade.

**Work:** extract lineage/preflight, target resource verification, downstream
verification coordination, and successor construction from
`release_bundle/verifier.rb` behind `ReleaseBundle::Verifier`. Apply the same
phase boundary to `release_bundle/applier.rb` only where duplication with the
verified execution lineage is demonstrated. Move bundle/portfolio live-status
input resolution to an application adapter so core live readers do not own
release parsing.

**Acceptance:** immutable predecessor/successor IDs, artifact order, target
rollups, retained partial evidence, source preflight order, and fail-before-read
behavior are unchanged; the release facade remains the supported API.

**Verification:** all release bundle model/CLI/apply/verify suites, aggregate
live status, exact plan, then full verification.

**Rollback:** collaborators are private implementation details wired through
the stable facade.

### STR-6: Provider Adapter Phase Collaborators

**Intent:** keep provider-specific growth isolated without generalizing unlike
providers.

**Work:** split `sloth/mcp/comparison.rb` into contract preflight, bounded
collection, semantic comparison, and report construction behind
`Sloth::Mcp::Comparison`. Split `appliers/manifest_bundle.rb` into managed-file
resource planning and exact execution/replay behind
`Appliers::ManifestBundle`. Preserve Datadog collaborators and do not refactor
them without live backend evidence.

**Acceptance:** tool allowlist/schema/version gates, pagination caps,
non-authoritative status, file operation order, noop behavior, exact-plan
replay, resume, external handoff, and final verification are unchanged.

**Verification:** Sloth MCP client/comparison/CLI, apply/import/diff/prune,
manifest execution/journal/exact-plan, and full verification.

**Rollback:** public provider adapter constructors and methods do not change.

### STR-7: Test Topology, Composition Roots, And Debt Closure

**Intent:** make the final architecture visible in load structure and failure
locality.

**Work:** split `test/cli_test.rb` by command family while keeping it as an
aggregate compatibility entry point. Add bounded-context load entry points and
reduce the root from 63 implementation requires to a small set of explicit
composition roots. Remove resolved exceptions from the architecture debt
allowlist, update C4/dependency documentation, rerun the structure report, and
close or explicitly defer every remaining hotspot.

**Acceptance:** focused failures identify one command/domain family; isolated
entry points load their declared dependencies; no forbidden cycle remains; the
root has at most 10 bounded-context requires; no user-visible test coverage or
public require path is lost.

**Verification:** isolated load smokes, architecture/dependency tests, every
focused family suite, aggregate Ruby suite, forbidden terms, and full
verification.

**Rollback:** keep `lib/slo_rules_engine.rb`, `lib/sre.rb`, `cli_test.rb`, and
all public constants as compatibility entry points.

## Use-Case Traceability

| Use cases | Preserved outcome | Main packets | Required evidence |
| --- | --- | --- | --- |
| UC-01, UC-02, UC-03 | telemetry-first discovery, review, and cross-provider handoff | STR-0, STR-3, STR-7 | telemetry, onboarding, walkthrough, provider-binding tests |
| UC-04 | deterministic complete provider delivery bundle | STR-0, STR-3, STR-7 | provider, manifest schema/review, CLI tests |
| UC-05 | immutable reviewed multi-provider release | STR-1, STR-4, STR-5 | release builder/schema/status tests |
| UC-06, UC-07 | drift and managed-state inventory | STR-3, STR-4, STR-6 | apply, state reader/planner, CLI tests |
| UC-08, UC-09 | durable journal and exact approved plan | STR-1, STR-4 | journal, transition, approved-plan, exact-plan tests |
| UC-10 | approved multi-target apply and verification | STR-2, STR-4, STR-5 | release apply/verify model and CLI tests |
| UC-11, UC-12 | reviewed apply and ownership-gated prune | STR-3, STR-4, STR-6 | provider-state execution and CLI tests |
| UC-13 | telemetry reality check | STR-0, STR-3, STR-7 | reality-check and telemetry lookup tests |
| UC-14 | contextual delivery routes | STR-0, STR-3, STR-7 | provider/integration and CLI tests |
| UC-15 | isolated Datadog sandbox validation | STR-0, STR-7 | sandbox, transport, state-reader tests; no live run required |
| UC-16 | reviewed Sloth downstream generated-rule identity | STR-1, STR-2 | downstream evidence model/CLI tests |
| UC-17 | live SLO/error-budget status | STR-1, STR-2, STR-5 | per-manifest, Sloth, aggregate, and CLI status tests |
| UC-18 | official Sloth MCP comparison | STR-1, STR-2, STR-6 | MCP client/comparison/CLI tests |
| UC-19 | Agent discovery and future structured invocation | STR-0, STR-3, STR-7 | registry, introspection, Human/Agent equivalence, roadmap tests |

`test/use_cases_documentation_test.rb` remains the guard that every use case
states concrete outputs and an intent or safety boundary.

## Contract Verification Matrix

| Contract area | Must remain stable | Evidence |
| --- | --- | --- |
| Neutral model and DSL | intent fields, defaults, validation paths | DSL, validation, reliability-model tests |
| Provider manifests | schema and deterministic artifacts for all providers | manifest/provider/walkthrough tests |
| Provider state | snapshots, changes, findings, summaries, results | provider-state contract and apply tests |
| Journals and approved plans | IDs, transition state, attempts, exact execution | journal, transition, approved-plan, exact-plan tests |
| Release bundles | lifecycle, content identity, source lineage, execution and verification artifacts | release suites |
| Sloth downstream evidence | exact identities, reviewed values, source freshness | Sloth evidence suites |
| Live status | objective, budget, burn, freshness, coverage, aggregation | live-status suites |
| Human/Agent command contract | 40 IDs, mappings, strict request schemas, side effects | registry/introspection/parity tests |
| Public safety | no credential values or private terminology | credential fixtures, forbidden-terms suite |

## Verification And Commit Policy

For every packet:

1. Record the exact pre-change public facade, schemas, findings, and focused
   tests.
2. Add or strengthen characterization before moving production code.
3. Make one responsibility move at a time and keep compatibility delegates.
4. Run the focused suites named in the packet.
5. Run `ruby -Ilib test/all_test.rb`, `ruby -Ilib
   test/forbidden_terms_test.rb`, and `./scripts/verify.sh` with the canonical
   Ruby path.
6. Run `git diff --check` and the deterministic structure report.
7. Update architecture, roadmap, AGENTS handoff, and engineering usage only
   when the supported scope or interface changes.
8. Commit and push the verified packet before starting the next packet.

No packet is complete because files became shorter. It is complete only when
the named dependency debt or responsibility is removed and preservation
evidence is green.

## Freeze Zones

The audit does not justify immediate work in these areas:

- `dsl/service_definition.rb`: large but stable nested DSL builders; split only
  when a new DSL feature creates a named collaborator and characterization.
- Datadog translation, planning, reading, transport, and risk collaborators:
  already separated; change only when isolated backend evidence identifies a
  contract or responsibility gap.
- onboarding artifact indexing and manifest review: currently cohesive; do not
  move them into generic artifact frameworks.
- local `fetch_value` helpers: preserve boundary-specific defaults and errors;
  do not replace them with one repository-wide hash abstraction.
- versioned schema validators: do not introduce a generic validation DSL during
  structural packets.

## Revalidation

The completed plan was checked a second time against the audit evidence,
project intent, the Agent Interface Roadmap, all 19 engineering use cases, and
the earlier accepted housekeeping deferrals.

Gaps found and corrected during revalidation:

1. A file-size-only plan would not stop new dependency cycles. STR-0 now adds a
   debt allowlist and forbids new boundary edges before extraction starts.
2. Splitting the root loader first would expose unresolved cycles without
   fixing ownership. Composition-root cleanup moved to STR-7 after cycle
   breakers.
3. Generic utility extraction could weaken boundary-specific failures. STR-1
   is limited to proven identical fingerprint and credential-key policy; local
   accessors and validators remain frozen.
4. Refactoring CLI parsing without an application seam would encourage Agent
   `argv` reconstruction. STR-3 now requires typed shared application commands
   and explicit schemas before structured invocation expands.
5. Release and Sloth file splits alone would retain the `ReleaseBundle ->
   LiveStatus` and `ProviderState -> ReleaseBundle` cycles. STR-2 and STR-4 now
   move preflight ownership and invert the default dependency explicitly.
6. A whole-project rewrite would be difficult to review and rollback. The plan
   now has eight independently verified checkpoints with stable facades and
   explicit rollback paths.
7. Stable DSL, Datadog, onboarding, and validation code did not show a safe
   current seam. They are freeze zones with growth triggers rather than
   speculative work.
8. The initial schema inventory counted repeated occurrences across files.
   STR-0 originally snapshotted 20 unique literal artifact schema IDs; its
   current guard snapshots 21 after the Agent result envelope was added and
   hashes the full command registry/catalog contracts separately.

Result: every observed hotspot is either assigned to a packet or explicitly
frozen with a trigger; every use case has preservation evidence; the next Agent
CLI feature has a structural seam; and no live provider work or product policy
change is hidden inside the refactoring program.
