# Historical maintainer audit

Original audit evidence recorded in the housekeeping plan at `611d450`.
Findings describe the September baseline, not current open task status.
Use the [current queue](../project-structure-refactoring-plan.md#ordered-housekeeping-queue).

### Current Audit Evidence

Inspected revision: `df5303e` (clean `main` before the original audit documentation).
Findings below describe that baseline; current task status and correction
evidence are recorded in the queue and task sections.

| Measure | Original audit | Rechecked 2026-09-05 |
| --- | ---: | ---: |
| Production Ruby/executable files | 82 | 100 |
| Production lines | 21,467 | 24,649 (+14.8%) |
| Test Ruby files, including support/aggregate files | 71 | 78 |
| Test lines | 16,092 | 17,732 |
| Root requires | 63 | 64 |
| Registered commands | 40 | 40 |
| Allowed forbidden-reference occurrences | not recorded here | 15 |

The command surface has not grown, but its interface machinery has. That is
not automatically waste: Agent confinement and parity need real code. However,
the dependency-removal packets remain open and the largest existing workflow
files remain large: downstream evidence 1,167 lines, journal execution 884,
release verification 828, and the CLI facade 774. STR-3 progress alone is not
evidence that the codebase is easier to understand.

Verified findings, ordered by practical impact:

1. **The aggregate test baseline is incomplete.** Loading `test/all_test.rb`
   and comparing `$LOADED_FEATURES` with `test/**/*_test.rb` identifies three
   omitted suites: `agent_telemetry_commands_test.rb`,
   `sloth_live_status_test.rb`, and `telemetry_batch_discovery_test.rb`.
   The aggregate passes 532 tests / 7,282 assertions; those suites separately
   pass another 17 tests / 158 assertions. Passing `scripts/verify.sh` therefore
   does not currently mean every test file ran. This is test discovery evidence,
   not a line-coverage measurement.
2. **There is no short, reliable maintainer entry point.** `AGENTS.md` was 974
   lines, this plan 581, and current priorities are repeated in implementation,
   Agent, adoption, and handoff documents. The implementation plan's STR-3
   summary still said seven shared commands while Phase 14 said thirteen.
   The latest two-command checkpoint touched 21 files, including nine Markdown
   files. Reading more historical status is not a substitute for a code map.
3. **Output safety is still field-by-field and incomplete.** In
   `application/onboarding_commands.rb`, `sanitize_signals` removes some
   untrusted text but passes `calculation_basis` through. `CandidateGenerator`
   copies it into `proposed_slo`. An in-memory application probe with confined
   Agent policy returned `{ "unexpected_text": "audit_canary" }` unchanged
   when supplied as that field. No source file or provider was accessed by the
   probe. This proves the application-boundary defect, not an end-to-end CLI
   exploit. Treat correction as a safety fix, not behavior-preserving cleanup.
4. **The architecture checks prove less than their prose suggests.**
   `StructureInventory#dependency_evaluation` evaluates configured regex rules;
   boundary `allowed_dependencies` are reported but not used to derive all
   forbidden edges. Use-case mapping checks file existence, not suite loading.
   Some removal ownership also disagrees: shared fingerprint edges are marked
   STR-2 in configuration but assigned to STR-1 here. The check is useful, but
   it is not a complete Ruby dependency graph or coverage proof.
5. **Repeated policy and parallel command declarations remain.** The new
   onboarding support adds another canonical JSON fingerprint implementation
   while STR-1 remains open. Command-family declarations coexist with legacy
   usage/example/schema assembly. This creates multiple maintenance paths even
   though the final runtime registry is validated.

### Ordered Housekeeping Queue

Audit verification (canonical Homebrew Ruby, 2026-09-05):

- `./scripts/verify.sh`: passed, including 532 tests / 7,282 assertions and
  architecture checks; its deliberately refused live apply printed expected
  usage text. No live provider verification was attempted.
- `ruby -Ilib -e 'Dir.glob("test/**/*_test.rb").sort.each { |path| require_relative path }'`:
  passed 549 tests / 7,440 assertions, zero failures/errors/skips. This audit
  command covers the omitted suites but does not repair the canonical runner.
- Focused housekeeping/Agent-roadmap/use-case/public-safety tests: 13 tests /
  653 assertions passed. `git diff --check` passed. Current suite success does
  not invalidate the separately reproduced, not-yet-regression-tested output
  defect above.
