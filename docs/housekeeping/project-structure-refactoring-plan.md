# Project Structure Refactoring Plan

Date: 2026-08-15

Status: active; STR-0 completed, STR-3 started

Baseline commit: `6dc0ffb`

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

Packet numbers are stable identifiers, not a requirement to pause product work
until every lower number ships. STR-0 is always first. STR-3 may then accompany
the next AICLI-F2 invocation slice because it is the feature-aligned seam.
Structural dependency order is STR-1 before STR-2/STR-4, STR-2 and STR-4 before
STR-5/STR-6, and STR-7 last. Only one packet is active at a time.

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
of full verification. `config/architecture_dependencies.json` assigns all 94
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

**Current progress (2026-08-15):** the complete catalog, analysis, and
provider-state families now own Human usage, Agent examples, and explicit
argument schemas in bounded declaration modules. `providers.list`,
`integrations.list`, `recommend-calculation-basis`, `validate`,
`migration-report`, `model-report`, and file-backed `diff` normalize Human
flags or Agent JSON into typed application commands that return values without
printing or exiting. Remaining command families still use the compatibility
assembly and keep STR-3 open.

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
