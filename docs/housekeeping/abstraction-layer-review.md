# Abstraction Layer Review

Reviewed 2026-10-05 against production code at `611d450`. Audience: the
maintainer deciding what to keep, consolidate, move, or remove. This is an audit;
the [housekeeping queue](project-structure-refactoring-plan.md#ordered-housekeeping-queue)
owns execution order. The [maintainer guide](../maintainer-guide.md) explains
how to navigate the current implementation.

HK-04 resolution update, 2026-10-05: A-01's shared policies now live in
`artifact_integrity.rb`; compatibility delegates preserve existing entry points.
The generic release-utility edges in A-04 are removed. The findings below describe
the inspected baseline; remaining responsibilities and dependencies stay open.
Verification and the exact before/after debt inventory live in
[HK-04](project-structure-refactoring-plan.md#hk-04-give-artifact-identity-and-credential-policy-one-owner).

**Conclusion:** the main domain boundaries are useful, but their implementation
is not fully consistent. The strongest simplifications are removing leftover
migration helpers, giving repeated policies one owner, and correcting
cross-boundary dependencies. A rewrite or a new generic framework is not
supported by this evidence.

## Method and limits

The audit compared three explanations for the maintenance burden: unnecessary
wrappers, justified responsibilities with inconsistent ownership, and misleading
navigation/documentation. It inventoried all production files, inspected the
core seams and dependency hotspots, checked repository call sites, compared
policy implementations with controlled inputs, and traced selected helpers
through the aggregate suite.

Observed: 100 production/executable files, 24,677 production lines, 64 root
requires, 40 registered commands, and 15 allowlisted forbidden-reference
occurrences. Thirteen commands have shared executable application mappings;
20 request schemas are explicit and 20 are inferred. These describe the baseline,
not targets or measures of comprehension. HK-04 adds one shared-policy file and
reduces the configured forbidden-reference occurrences from 15 to 6.

The structure check enforces configured regex rules, file ownership, and
contract snapshots. It is not a complete Ruby dependency analyzer. The runtime
trace covers the parent test process; child-process and external library calls
are excluded. No performance claim or live-provider verification is made.

## Current Layer Map

| Boundary | Why it exists | Assessment |
| --- | --- | --- |
| Composition | Register providers and assemble library dependencies | Necessary; the 64 implementation requires obscure independent loading. Defer composition-root changes to STR-7. |
| Human/Agent interfaces | Parse requests, resolve commands, render results, enforce interface policy | Necessary; shared application commands coexist with legacy orchestration and unused migration helpers. |
| Neutral intent | Define reliability policy independently of a provider | Consistent in the inspected code and configured checks; retain DSL, model, validation, and burn policy. |
| Telemetry/onboarding | Convert observations into proposals and reviewed intent | Necessary; keep evidence separate from accepted policy. |
| Provider translation and backend adapters | Translate intent and communicate with providers | Necessary; the boundary map also puts Datadog state collaborators here, contradicting its declared dependency restrictions. |
| Application commands | Share workflow behavior between Human and Agent adapters | Necessary even when a command is short; provider-validation orchestration is duplicated. |
| Artifact review | Validate artifact shape, provenance, and current review evidence | Necessary; schema validity and current reviewed meaning are distinct checks. |
| Provider state | Represent desired/observed state, changes, execution, and journals | Necessary; one default dependency points back to release orchestration. Legacy plan adapters have compatibility value. |
| Release orchestration | Coordinate reviewed multi-target lineage, apply, and verification | Necessary; evidence preflight reaches into concrete live-status readers, and the verifier mixes several phases. |
| Live status | Read measured attainment, budget, burn, and freshness | Necessary; bundle/portfolio input resolution and generic integrity policy are owned in the wrong places. |
| Sloth evidence/runtime | Prove generated-rule identity and compare provider evidence | Necessary for implemented workflows; pure evidence preflight should be owned by evidence, and common integrity policy should be provider-neutral. |

## Findings

### A-01: Identical policy has multiple owners

Canonical JSON hashing is implemented in
[ProviderState](../../lib/slo_rules_engine/provider_state.rb),
[ReleaseBundle](../../lib/slo_rules_engine/release_bundle/fingerprint.rb),
[manifest review](../../lib/slo_rules_engine/manifest_review_queue.rb), and
[OnboardingCommandSupport](../../lib/slo_rules_engine/application/onboarding_commands.rb).
The ProviderState and ReleaseBundle credential scanners also duplicate the
same key predicate and recursive path traversal.

Controlled vectors covering key order, nesting, arrays, symbol values,
string/symbol key collisions, and strings produced equal JSON hashes after
removing the onboarding `sha256:` prefix. Both scanners returned equal paths
for a synthetic nested fixture. That demonstrates consolidation candidates,
not interchangeability for every input.

**Decision:** HK-04 should give proven-identical JSON hashing and credential-key
policy one neutral owner, preserving public delegates, prefixes, error
fallbacks, and IDs. Include manifest-review hashing in the inventory. Keep text
hashing and bundle-specific identity assembly distinct: a telemetry identifier's
text hash is not the hash of its JSON string representation. Local hash accessors
also have different defaults and accepted containers; do not merge them merely
because their names match.

**Resolution:** implemented in HK-04. Pre-extraction goldens remain unchanged.
A Hash subclass characterization additionally proves onboarding's `fetch`
differs from bracket reads; the shared canonicalizer preserves both explicitly.
The onboarding serialization-error fallback remains at its application boundary.

### A-02: Three CLI helpers are leftovers from migration

`RulesCtl.resolve_review_manifests`, `RulesCtl.write_provider_manifests`, and
`RulesCtl.write_manifest_review_report` in
[cli.rb](../../lib/slo_rules_engine/cli.rb) have no repository call sites from
current workflows. The last writer is referenced only by the other unused
writer. Generation and review now use
[application/generation_commands.rb](../../lib/slo_rules_engine/application/generation_commands.rb).
The aggregate parent-process trace observed the application writer and zero
calls to those three RulesCtl helpers.

**Decision:** these are concrete removal candidates for an isolated HK-05
preservation checkpoint. Check public-library compatibility before deletion;
absence of repository callers does not prove absence of external callers.
Keep `load_definitions`, `validate_for_provider`, and `write_json_file` until
their current legacy callers are migrated. They are still used.

### A-03: The command registry has one runtime inventory but two authoring paths

[CommandRegistry.default](../../lib/slo_rules_engine/cli/command_registry.rb)
builds from `CommandCatalog.definitions`. That catalog still owns legacy Human
usage, Agent examples, full declarations, and assembly alongside six dedicated
`cli/command_contracts/` families. It is both a definition factory and a compact
projection. [CommandSchemas](../../lib/slo_rules_engine/cli/command_schemas.rb)
infer arguments for the 20 legacy declarations.

A concrete limitation: the inferred `bundle.verify` schema requires
`sloth_evidence_files`, `target_base_urls`, and `max_age_seconds`, although the
Human file-backed form supports omitting downstream evidence/runtime inputs.
That command is not Agent-executable, so this is planned-contract inconsistency,
not a currently enabled invocation failure.

**Decision:** retain immutable definitions, the validated registry, and the
catalog view. Complete HK-05 family ownership and derive the compact catalog
from those declarations. Characterize optional/conditional forms separately
when correcting schemas; do not silently refresh snapshots during a structural
move. Do not replace this with handler discovery or a generic command framework.

**Resolution:** HK-05 moves all remaining declarations into owning families and
removes example-based inference. All 40 resolved schemas, examples, handlers,
and safety metadata retain their baseline values; only authoring-source labels
change. The optional/conditional schema limitations remain separately gated.

### A-04: Useful domains depend on each other in the wrong direction

[ApprovedPlan::Builder](../../lib/slo_rules_engine/provider_state/approved_plan.rb)
defaults to `ReleaseBundle::StatusEvaluator`. Release code consumes provider
state, so this creates a dependency back into its orchestrator.

[SlothReader.preflight](../../lib/slo_rules_engine/live_status/sloth_reader.rb)
validates local evidence without querying telemetry. Release building,
verification, and Sloth MCP comparison instantiate this live reader to use that
preflight. Meanwhile Sloth evidence and live aggregation use ReleaseBundle's
hashing/scanner utilities. These relationships produce cycles between release,
provider state, live status, and Sloth evidence/runtime.

**Decision:** move shared integrity policy in HK-04, evidence preflight in
HK-07/STR-2, and the source-bundle status dependency to the application composition
boundary in HK-08/STR-4. STR-5 moves bundle/portfolio input resolution out of core
status readers. Keep runtime querying in status and multi-target coordination
in release. Separating ownership removes these edges without adding a universal
workflow engine.

### A-05: Provider validation is repeated in three active paths

The core/provider validation loop is repeated in `RulesCtl.validate_for_provider`,
`Application::ProviderGenerationSupport`, and `Application::DiffProviderState`.
The implementations aggregate the same error/warning shapes. Controlled probes
using the public checkout definition returned identical results for all three
providers.

**Decision:** give this orchestration one application-level owner when migrating
its callers in HK-05. Preserve finding paths, ordering, warning behavior, and
Human/Agent exits. Keep core validation separate from provider validation;
those two policies answer different questions.

### A-06: The boundary declarations and their enforcement disagree

[StructureInventory](../../scripts/support/structure_inventory.rb) reports
`allowed_dependencies` but evaluates only separately configured regex rules.
[The map](../../config/architecture_dependencies.json) assigns all `datadog/`
files to `provider_translation`, allowed to depend only on `neutral_intent`.
The actual `datadog/state_verifier.rb` aliases `ProviderState::Value` and
`ProviderState::Fingerprint`, and the state planner uses shared apply operations.
The provider-generation regex excludes `datadog/`.

An isolated fixture assigned to that same boundary with a `ProviderState::Value`
reference passed the three general domain/provider rules despite contradicting
the declaration. This reproduces the scope gap without changing production
files or widening an allowlist.

**Decision:** HK-06 must reconcile Datadog state ownership with the map, add
negative fixtures for declared restrictions, and align STR removal ownership.
Document intentional limitations. This needs bounded rule coverage, not a
complete Ruby analyzer. A green current check means recorded debt has not
changed; it does not mean every layer restriction is enforced.

### A-07: Some navigation problems are file organization, not extra layers

`journal_execution.rb` already separates `JournalTransitioner`, `JournalStore`,
`ResultBuilder`, and `JournaledExecutor`. Those are different responsibilities:
legal transitions, atomic storage, result construction, and operation execution.
Sloth evidence similarly has existing builder, validator, and freshness roles.
Keeping these roles is justified; finding them in large combined files is hard.
The release verifier additionally combines lineage preflight, resource checks,
downstream evaluation, and successor construction in one facade.

**Decision:** use HK-07/08 and later STR-5/6 to expose existing responsibilities
behind stable entry points. File-only decomposition should not add another
public class hierarchy. Do not split the stable DSL or provider generators to
meet a line-count target.

## Accepted Deferrals

Keep the provider contract and three adapters: live API reconciliation, managed
files, and external-generator handoff have different semantics. Keep review,
approval, journal, and verification objects: they represent separate trust and
lifecycle boundaries. Keep `ApplyPlan`/`ApplyOperation` as compatibility adapters
while the shared state contract is consumed; a rename-and-delete migration
would affect saved Human output and exact-plan execution.

The thin application commands, `Context`, and `CommandResult` are useful
interface boundaries. No evidence here supports removing them, making a generic
registry for providers and integrations, or generalizing unlike providers.
Datadog live testing and tagged Sloth MCP comparison remain externally gated.

## Recommendations

Keep HK-02's human navigation check open, then follow the existing queue:
HK-04's common policy extraction is implemented; HK-05 covers single command ownership, leftover helpers,
and proven duplicated orchestration; HK-06 for enforcement scope; then reassess
with the maintainer. HK-07/08 address the demonstrated dependency problems.
Later STR packets retain their dependencies and preservation gates.

## Verification evidence

On 2026-10-05, the aggregate suite passed 558 tests / 7,550 assertions under
selected-helper tracing; the offline Prometheus walkthrough passed one test /
47 assertions. `scripts/structure-report --check` passed with its stated scope.
No backend queries, metric/log/trace reads, or provider mutation were performed.
Audit fixtures were isolated and deleted on completion. Production code is
unchanged; rollback of this audit is a documentation-only revert.

Local outputs: `/tmp/slo-abstraction-audit-20261005-structure.json`,
`/tmp/slo-abstraction-audit-20261005-kernel-probes.json`,
`/tmp/slo-abstraction-audit-20261005-helper-trace.json`,
`/tmp/slo-abstraction-audit-20261005-boundary-probe.json`, and
`/tmp/slo-abstraction-audit-20261005-tests.log`. Hash/validation probes cover
controlled inputs; full consolidation still requires the queue's golden vectors
and artifact compatibility checks.

## Historical review

The [June review and July completion update](archive/abstraction-layer-review-2026-07-28.md)
are preserved with the original file digest. Their extraction order is historical;
the current housekeeping queue takes precedence.

<a id="completion-update-2026-07-28"></a>
<a id="blockers"></a>
<a id="important-gaps"></a>
<a id="suggested-extraction-order"></a>
<a id="next-useful-slice"></a>

Earlier anchors now point here. See the archived
[completion update](archive/abstraction-layer-review-2026-07-28.md#completion-update-2026-07-28),
[findings](archive/abstraction-layer-review-2026-07-28.md#findings),
[extraction order](archive/abstraction-layer-review-2026-07-28.md#suggested-extraction-order),
and [next slice](archive/abstraction-layer-review-2026-07-28.md#next-useful-slice)
for their original text.
