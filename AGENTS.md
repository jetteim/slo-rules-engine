# AGENTS.md

## Purpose

This is a public-safe SLO rules engine. A neutral Ruby DSL expresses reliability
intent; providers translate it into artifacts. Reviewed state workflows compare,
plan, apply, prune, journal, and verify changes. Live status observes reliability.
Start with the [maintainer guide](docs/maintainer-guide.md) for the code map.

## Current Priority Order

1. Follow the [housekeeping queue](docs/housekeeping/project-structure-refactoring-plan.md#ordered-housekeeping-queue).
   It is the single owner of current execution order and task evidence.
2. Keep additional Agent command coverage and MCP/skill delivery paused through
   the first tranche; reassess with the maintainer after HK-01–HK-06.
3. Resume production-grade Datadog reconciliation only with isolated backend
   evidence. Live Datadog sandbox testing remains postponed by the user.
4. Extend Datadog exact-plan apply/resume only after verified backend recheck
   and idempotency semantics exist.
5. Revalidate Sloth MCP against a tagged binary only after an official release
   includes the upstream server. Its comparison remains non-authoritative.

## Non-Negotiable Working Rules

- Keep the repo public-safe. Private/internal rules are reference material only
  and must not be copied in. Never print, persist, or commit credentials.
- Prefer the neutral DSL and provider contract over provider-specific policy.
- Commit and push often; keep each checkpoint independently reviewable.
- Add verification evidence before claiming a checkpoint complete. Record the
  target, command, timestamp, output path, rollback path, and relevant telemetry
  names; state when no metric/log/trace or provider reads were performed.
- Follow the task's preservation, dependency, compatibility, and rollback gates.
  Do not split files only for size or refresh snapshots to hide contract drift.
- Update this file when operating rules or handoff guidance materially change;
  update task status and checkpoint evidence in the queue, rather than copying
  feature inventories here.
- Keep README.md and docs/use-cases.md current when command scope, provider
  output, workflow behavior, or safety boundaries change. Organize usage around
  engineering tasks.
- Every CLI change must update both the Human CLI and Agent CLI sub-interfaces,
  their shared registry/schema metadata, equivalence tests, runtime
  introspection, and usage in the same checkpoint. For gated commands, update
  the target mapping and parity inventory; once MCP ships, update its generated
  projection too.

## Runtime And Safety Boundaries

- The neutral model owns intent; providers own translation. Telemetry proposes
  candidates; human review accepts reliability policy.
- Confirmed apply/prune requires reviewed manifest provenance, applicable
  review freshness and ownership checks, and durable journal evidence. Plan or
  diff before mutation. Preserve deterministic operation order and stop after
  the first execution failure.
- File-backed exact execution preserves approved operations, immediate state
  recheck, scope locking, attempts, replay/resume policy, and final verification.
  Completed plans replay only after fresh convergence; failed plans require
  explicit journal-eligible resume.
- Release transitions retain immutable predecessors, content-derived identity,
  exact source/target lineage, and per-target evidence. Bundle apply/verify
  support file-backed targets; live or mixed bundles remain refused.
- Sloth engine-owned inputs and downstream state are distinct. Generation is
  external and pending unless exact reviewed generated evidence plus GET-only
  Prometheus reads proves downstream state. Do not execute Sloth implicitly.
- Live status requires reviewed intent and source/runtime preflight before
  client construction. Preserve all five states, partial evidence, coverage
  gaps, sanitized failures, and endpoint exclusion from persisted reports.
- Agent requests remain strict, bounded, and workspace-confined with path,
  symlink, URL/host, and identifier checks. Only registry-enabled application
  mappings may execute; adapter stdout/stderr and exit attempts are quarantined.
- `validate_only` checks the applicable request/policy contract with zero file
  writes, provider calls, or credential loading. Implemented zero-I/O paths
  also avoid source reads; observational plans declare their state reads.
- Candidate output retains explicit field allowlists, enum calculation basis,
  limits, truncation, and fingerprint quarantine. Handoff review returns a
  bounded summary and preserves packet identity and review evidence.
- Official Sloth MCP is comparison-only provider evidence. It cannot replace
  neutral status or the planned engine MCP adapter.

## Current State Summary

Use the [maintainer guide](docs/maintainer-guide.md) for current flows and source
ownership, [architecture](docs/design.md) for boundaries, and
[engineering use cases](docs/use-cases.md) for procedures and exact outputs.
Executable Agent support and safety metadata are available through
`bin/rules-ctl agent catalog` and `bin/rules-ctl agent describe COMMAND_ID`.
A catalog example is not proof that structured invocation is enabled.

## Most Recent Checkpoints

Task implementation and verification evidence live in the
[housekeeping queue](docs/housekeeping/project-structure-refactoring-plan.md#ordered-housekeeping-queue).
The [current abstraction audit](docs/housekeeping/abstraction-layer-review.md)
records duplication and dependency inconsistencies with reproducible evidence.
Earlier feature checkpoints and handoff inventories are preserved in the
[archived AGENTS.md](docs/housekeeping/archive/agents-2026-10-05.md).

## Current Open Gaps

The queue owns open housekeeping work. The
[Agent roadmap](docs/agent-interface-roadmap.md#feature-packets) owns remaining
Agent/MCP feature gates. The [implementation history](docs/implementation-plan.md)
records delivered scope and deferred provider work. Keep Datadog live work and
tagged Sloth comparison externally gated as described above.

## Recommended Next Slice

Follow the first open acceptance item in the queue. HK-02's guide and navigation
cleanup are implemented; maintainer comprehension remains unverified until the
three navigation tasks are tried. HK-06 is the next code task after the completed
policy and command-ownership checkpoints. Do not automatically
resume feature expansion after a documentation change.

## Next Session Handoff

Read the guide and current queue, inspect the working tree and recent commits,
and load only the owning code/tests for the selected task. Avoid rereading
archived feature inventories as current instructions. Before a CLI change,
inspect its declaration, Human handler, application mapping, Agent invocation,
input policy, and equivalence tests using the guide's trace.

## Verification Commands

Run the owning focused tests first, then the checkpoint gates:

```bash
scripts/structure-report --check
git diff --check
./scripts/verify.sh
git status -sb
```

The aggregate discovers every `test/**/*_test.rb` suite. The structure check
validates configured regex restrictions, ownership, and snapshots; it does not
prove a complete Ruby dependency graph or general coverage. Explain the exact
contract change before updating a digest. Run the
[offline Prometheus walkthrough test](test/prometheus_stack_walkthrough_test.rb)
when changing its documented flow.

## Resume Checklist

1. Read the [guide](docs/maintainer-guide.md) and the queue's current task.
2. Inspect `git status -sb` and the latest commits; preserve unrelated work.
3. Read the task's owning facade, focused tests, and preservation gates.
4. Execute one reviewable checkpoint, capture evidence, update task status, and
   commit/push. Record accepted deferrals and unverified human feedback clearly.
