# SLO Rules Engine

Public-safe SLI/SLO engineering toolkit with a Ruby DSL, telemetry-first onboarding, provider artifact generation, release-bundle planning, and explicit provider-state workflows.

The engine keeps reliability intent independent from observability products. Provider adapters translate reviewed intent into complete backend bundles; they do not choose objectives, success conditions, or response policy.

## Engineering Tasks

Use the toolkit to:

- inventory service telemetry and find plausible SLI/SLO candidates
- turn accepted candidates into a reviewed service definition
- reuse discovery evidence from one backend while targeting another backend
- generate SLO evaluation, alerting, dashboard, and routing artifacts
- package review evidence and provider plans into a content-addressed release bundle
- approve one file-backed provider target and execute only its reviewed operations
- execute every approved file-backed target and persist one immutable applied release
- recheck an applied file-backed release and persist immutable verification evidence without rewriting managed state
- compare reviewed desired state with existing backend or managed-file state
- persist a deterministic operation journal from one verified dry-run provider plan
- apply or prune reviewed artifacts through explicit confirmed workflows
- run telemetry reality checks before treating an SLO as operationally ready
- capture reviewed, content-addressed Sloth generated-rule identity without
  running Sloth or contacting Prometheus
- cross-check exact reviewed Sloth identities, objectives, periods, budget,
  burn, and availability against the official read-only Sloth MCP runtime
- read current Prometheus-compatible SLO attainment, remaining error budget,
  burn rate, and telemetry freshness from one reviewed Prometheus Stack or
  evidence-linked Sloth manifest, release bundle, or portfolio
- validate Datadog credentials and dashboard reconciliation in an isolated
  sandbox before relying on live provider behavior
- inspect the current Human/Agent command contract and strict request schema
  offline before an agent constructs a request

The detailed commands, expected files, and safety boundaries are in [Engineering Use Cases](docs/use-cases.md).

Phase 14 now has a validated 40-command catalog and registry. It pairs each
Human CLI example with an Agent CLI JSON request, owns Human command dispatch,
and exposes bounded offline `agent catalog` plus exact `agent describe`
introspection with a strict resolved request schema for every command. The
[Agent Interface Roadmap](docs/agent-interface-roadmap.md) defines the remaining
structured invocation, result envelopes, input hardening, bounded and sanitized
output, versioned agent skill, and later MCP projection.

The repository-wide [Project Structure Refactoring Plan](docs/housekeeping/project-structure-refactoring-plan.md)
records the measured dependency cycles and responsibility hotspots, maps all 19
engineering use cases to preservation tests, and sequences eight reversible
packets so Agent and provider growth do not deepen implicit coupling.

## Provider Outputs

| Provider | Generation output | Dry-run planning output | Confirmed state output |
| --- | --- | --- | --- |
| `datadog` | Reviewed manifest containing SLOs, burn-rate monitors, missing-telemetry monitors, dashboards, and route context | Versioned desired/observed state plus API-oriented `create`, `update`, `recreate`, or `noop` operations with ownership evidence and provider risk | Datadog resources, durable operation journal, and a `ProviderStateResult` with backend identity and canonical payload/absence verification |
| `prometheus_stack` | Reviewed manifest containing evaluation-window SLI/SLO/remaining-budget recording rules, burn-rate and telemetry-gap alerts, Grafana dashboards, and Alertmanager route intent | Versioned desired/observed state plus `write` or `noop` operations for the manifest and every native bundle file | Managed JSON/YAML files, durable operation journal, and a `ProviderStateResult` with post-write/delete convergence evidence |
| `sloth` | Reviewed manifest containing Sloth `prometheus/v1` SLO specs | Versioned desired/observed state plus `write` or `noop` operations for the manifest and native Sloth input, and an external-generator handoff | Verified engine-owned files and durable journal/result; optional reviewed evidence plus read-only Prometheus status can verify downstream generated state, and an official MCP runtime can produce a supplemental comparison report |

All providers also emit a saved provider-level manifest-review report when `generate --output-dir` is used.

All provider dry-run plans can be converted into
`slo-rules-engine/provider-operation-journal/v1` JSON. Datadog journals
preserve resource IDs, ownership identity, and risk; Prometheus Stack journals
preserve managed-file verification requirements; Sloth journals also identify
the external-generator handoff as requiring manual verification.

Prometheus Stack and Sloth targets in an `apply_ready` release bundle can also
be converted into an immutable
`slo-rules-engine/approved-provider-plan/v1` artifact. Exact apply rechecks
managed-file state under a per-scope lock, rejects drift, executes only the
stored operations, and links the approved plan to the durable operation
journal. Datadog exact apply remains deferred until its live backend recheck
contract is verified.

When every target is file-backed, `bundle apply` requires one approved plan per
target, validates the complete approval set before any write, executes targets
in stable UID order through the same exact-plan boundary, and writes a new
content-addressed `applied` bundle containing one execution-result artifact per
target. Mixed or Datadog live-API bundles are rejected before execution.

`bundle verify` turns a valid file-backed `applied` bundle into an immutable
content-addressed `verified` successor only after fresh read-only convergence
checks. It validates packaged plan, execution, runtime, and full journal
fingerprints before reading managed state, then records one
`target_verification` artifact per target under
`slo-rules-engine/bundle-target-verification/v1`. Prometheus Stack and Sloth
engine-owned files must converge. Sloth downstream state remains pending unless
the command receives current exact evidence plus an explicit read-only
Prometheus-compatible runtime; complete live bindings then produce
`external_status: succeeded`. Datadog and mixed live/file bundles are rejected
before target reads.

After an operator runs Sloth externally, `sloth-evidence capture` can bind the
reviewed manifest and native input fingerprints to the saved generated
Prometheus recording rules. The content-addressed artifact preserves exact
objective, budget, burn, metadata, error-ratio, observation-query, and
freshness bindings. `sloth-evidence status` rereads those local sources and
fails when their semantic fingerprints drift. Direct Sloth `status` consumes
only this fresh evidence and an explicit Prometheus runtime. `bundle create`
can package one current evidence artifact per Sloth target for aggregate status,
and `bundle verify` can attach the same evidence while proving downstream state
through read-only live status.

## Usage By Use Case

### Find SLO candidates for an existing service

Discover live telemetry, rank candidate signals, and create a review queue:

```bash
bin/rules-ctl discover-telemetry \
  --provider=datadog \
  --scope-file=./examples/telemetry/scopes.json \
  --output-dir=./work/discovery

bin/rules-ctl onboarding-summary \
  --handoff-dir=./work/handoff \
  ./work/discovery/index.json
```

This produces normalized discovery evidence, candidate confidence and findings, an aggregate readiness index, and one reviewable handoff packet per scope.

### Generate another provider from discovered evidence

Discovery provider and delivery provider are intentionally separate. For example, use Datadog evidence to decide which SLO is worth defining, then bind the accepted SLI to Prometheus metrics and generate a Prometheus Stack bundle:

```bash
bin/rules-ctl review-handoff \
  --accept=request-latency \
  --reject=request-traffic \
  --note='Latency is the user-visible signal to carry forward.' \
  ./work/handoff/checkout-prod.handoff.json

bin/rules-ctl draft-from-handoff \
  --service=checkout-api \
  --owner=payments-platform \
  ./work/handoff/checkout-prod.handoff.json \
  > ./work/checkout-api.rb

# Review the draft, add a prometheus_stack provider_binding and Alertmanager route,
# then validate and generate the target provider.
bin/rules-ctl validate ./work/checkout-api.rb
bin/rules-ctl generate \
  --provider=prometheus_stack \
  --output-dir=./work/generated \
  --handoff-dir=./work/handoff \
  ./work/checkout-api.rb
```

The engine preserves Datadog as the evidence provenance and generates Prometheus artifacts from the reviewed Prometheus binding. It does not guess metric-name or query translations between backends.

The same reviewed definition can contain bindings for `datadog`, `prometheus_stack`, and `sloth`, allowing one accepted SLO to fan out into several provider bundles.

### Review and plan a release

Build the saved artifact index, create an immutable review bundle, then plan against current managed state:

```bash
bin/rules-ctl onboarding-artifact-index \
  --handoff-dir=./work/handoff \
  --draft-dir=./work/drafts \
  --manifest-dir=./work/generated \
  --provider=prometheus_stack \
  --provider=sloth \
  --output=./work/artifact-index.json \
  ./work/discovery/index.json

bin/rules-ctl bundle create \
  --artifact-index=./work/artifact-index.json \
  --reviewer=team/payments-sre \
  --reviewed-at=2026-07-26T09:30:00Z \
  --output=./work/review-ready.json

bin/rules-ctl bundle plan ./work/review-ready.json \
  --target-output=checkout-api/prometheus_stack=./managed \
  --target-output=checkout-api/sloth=./managed \
  --output=./work/apply-ready.json
```

The planned bundle contains generated dry-run plans and provider-level total, actionable, destructive, and risk summaries. Planning does not change the predecessor bundle or provider state.

### Approve and execute one exact file-backed plan

Approve one reviewed target from the `apply_ready` bundle:

```bash
bin/rules-ctl plan approve ./work/apply-ready.json \
  --target=checkout-api/prometheus_stack \
  --reviewer=team/payments-sre \
  --reviewed-at=2026-07-27T14:00:00Z \
  --note='Managed-file changes reviewed.' \
  --output=./work/approved-prometheus-stack-plan.json

bin/rules-ctl plan status ./work/approved-prometheus-stack-plan.json
```

Execute only the approved operations:

```bash
bin/rules-ctl plan apply ./work/approved-prometheus-stack-plan.json \
  --confirm \
  --journal-dir=./work/journals
```

After a partial file-write failure has been inspected and its environmental
cause corrected, resume only journal-declared eligible operations:

```bash
bin/rules-ctl plan resume ./work/approved-prometheus-stack-plan.json \
  --confirm \
  --journal-dir=./work/journals
```

Approval writes a content-addressed artifact containing the selected target,
review attestation, bundle lineage, manifest/review/handoff fingerprints, exact
dry-run provider plan, and managed output directory. Apply first rechecks the
managed-file plan fingerprint. Drift returns `stale_approved_plan` before a
journal or provider mutation; a concurrent apply for the same scope returns
`approved_plan_scope_busy`. Successful stdout contains the live
`ProviderStateResult`, the approved-plan reference, and the durable journal
path. The journal preserves both the live execution-plan identity and the
approved dry-run plan identity. Reapplying a completed plan rechecks current
state and returns the existing verified journal/result without rewriting files.
Partial or failed journals return `approved_plan_requires_resume` with manual
rollback guidance; they are never retried implicitly. `plan resume` preserves
attempt history, proves earlier successes still converge, retries only
resumable file writes, and re-verifies the complete engine-owned file set.

### Apply and verify an approved multi-target file release

Approve each target from the same file-only `apply_ready` bundle, then execute
the bundle:

```bash
bin/rules-ctl plan approve ./work/apply-ready.json \
  --target=checkout-api/prometheus_stack \
  --reviewer=team/payments-sre \
  --reviewed-at=2026-07-27T14:00:00Z \
  --output=./work/approved-prometheus-stack-plan.json

bin/rules-ctl plan approve ./work/apply-ready.json \
  --target=checkout-api/sloth \
  --reviewer=team/payments-sre \
  --reviewed-at=2026-07-27T14:00:00Z \
  --output=./work/approved-sloth-plan.json

bin/rules-ctl bundle apply ./work/apply-ready.json \
  --confirm \
  --approved-plan=./work/approved-prometheus-stack-plan.json \
  --approved-plan=./work/approved-sloth-plan.json \
  --journal-dir=./work/journals \
  --output=./work/applied.json

bin/rules-ctl bundle verify ./work/applied.json \
  --sloth-evidence=checkout-api/sloth=./work/sloth-evidence/checkout-api.json \
  --target-base-url=checkout-api/sloth=http://localhost:9090 \
  --max-age-seconds=300 \
  --output=./work/verified.json
```

Success writes and prints the immutable `applied` successor. Its target entries
reference generated `execution_result` artifacts containing the approved-plan
reference, durable journal reference, and terminal `ProviderStateResult`;
summary fields include execution counts by status. Prometheus Stack and Sloth
engine-owned files are written, while Sloth downstream generation remains an
external handoff.

Verification rereads the approved engine-owned JSON/YAML files without changing
their modification times, journals, or predecessor bundle. Success writes and
prints `verified.json`, whose targets reference generated
`target_verification` artifacts containing fresh expected/actual fingerprints,
`engine_owned_status: succeeded`, and either `external_status: pending` when no
Sloth runtime is requested or `external_status: succeeded` when current exact
evidence and all persisted live bindings are complete. The full neutral status
report and evidence identity are saved; the runtime URL is not. The summary
includes verification counts by status.

Missing, duplicate, unknown, or bundle-mismatched approvals; stale bundle
sources; live-API targets; and incompatible existing output files fail before
the first target executes. Execution stops at the first incomplete target and
prints that target plus earlier completed target results without writing
`applied.json`. Inspect and resume the failed approved plan with `plan resume`,
then rerun `bundle apply`. Completed targets replay from their verified journals
without file rewrites.

Missing, unreadable, or changed managed files fail
`bundle_target_verification_failed` without writing `verified.json`. Invalid
journal, lineage, runtime, plan, or execution evidence fails preflight before
managed reads. Live or mixed targets fail `unsupported_bundle_verify_target`.
An incompatible `verified.json` fails before reads and is never overwritten;
repeating an engine-only converged verification against a compatible output
returns identical bytes. Use a new output path for a later live downstream
snapshot because status values and sample timestamps are immutable evidence.

### Persist an operation journal

Create one journal from a saved single-manifest dry-run plan:

```bash
bin/rules-ctl apply \
  --provider=prometheus_stack \
  --dry-run \
  --output-dir=./managed \
  --manifest=./work/generated/checkout-api/prometheus_stack/manifest.json \
  > ./work/prometheus-stack-plan.json

bin/rules-ctl journal create \
  ./work/prometheus-stack-plan.json \
  --output=./work/prometheus-stack-journal.json

bin/rules-ctl journal status ./work/prometheus-stack-journal.json
```

The initial journal is deterministic, verifies the saved state and plan
fingerprints, records every operation as `pending` or `skipped`, and states
whether an uncertain failure could be retried after a state refresh. Standalone
journal creation and status assessment are read-only.

Every confirmed provider mutation requires a durable journal directory and
records live operation outcomes automatically:

```bash
bin/rules-ctl apply \
  --provider=prometheus_stack \
  --confirm \
  --output-dir=./managed \
  --journal-dir=./work/journals \
  --manifest=./work/generated/checkout-api/prometheus_stack/manifest.json
```

The command writes one journal under
`./work/journals/<service>/<provider>/`, transitions each operation atomically,
and includes a linked `ProviderStateResult` in stdout. Datadog journals record
returned resource IDs, request method/path, response fingerprints, and
public-safe failures, then reread backend state and compare provider identity
and canonical payload or confirmed delete absence. Prometheus Stack and Sloth
reread each attempted engine-owned file and record expected and actual state
fingerprints. Execution stops on the first operation failure and exits nonzero
for partial execution or verification drift. No-op resources retain their
immediately pre-execution convergence evidence. Sloth's downstream generator
remains pending. Exact execution, completed-plan replay, and explicit
file-backed partial-failure resume are available through the separate
approved-plan workflow above. Datadog resume and non-resumable operation retry
remain unsupported.

### Inspect or reconcile provider state

Use a reviewed provider manifest for all state work:

```bash
bin/rules-ctl diff \
  --provider=prometheus_stack \
  --output-dir=./managed \
  --manifest=./work/generated/checkout-api/prometheus_stack/manifest.json

bin/rules-ctl import \
  --provider=prometheus_stack \
  --output-dir=./managed \
  --manifest=./work/generated/checkout-api/prometheus_stack/manifest.json

bin/rules-ctl apply \
  --provider=prometheus_stack \
  --confirm \
  --output-dir=./managed \
  --journal-dir=./work/journals \
  --manifest=./work/generated/checkout-api/prometheus_stack/manifest.json \
  --handoff-dir=./work/handoff \
  --review-report=./work/generated/manifest-review/prometheus_stack.json
```

`diff`, `import`, and dry-run planning are observational. Confirmed `apply` and
`prune` are the mutation boundaries and require reviewed manifests; current
handoff and report evidence can be required as additional gates. Every
confirmed provider mutation also requires `--journal-dir`.

### Check whether the SLO is supported by real telemetry

```bash
bin/rules-ctl reality-check \
  --provider=prometheus_stack \
  --online \
  --base-url=http://localhost:9090 \
  ./work/checkout-api.rb
```

The report identifies missing metrics, absent series, incomplete histogram evidence, and other provider-binding gaps. It does not silently adjust the reviewed objective or calculation basis.

### Review Sloth-generated recording rules

After running the external `sloth generate` handoff, bind its saved output back
to the reviewed engine artifacts:

```bash
bin/rules-ctl sloth-evidence capture \
  --manifest=./managed/checkout-api/sloth/manifest.json \
  --input=./managed/checkout-api/sloth/generated/sloth.yaml \
  --generated-rules=./work/sloth-output/checkout-api-rules.yaml \
  --reviewer=team/payments-sre \
  --reviewed-at=2026-08-04T12:00:00Z \
  --output=./work/sloth-evidence/checkout-api.json

bin/rules-ctl sloth-evidence status \
  ./work/sloth-evidence/checkout-api.json
```

Capture prints and saves the same
`slo-rules-engine/sloth-downstream-evidence/v1` JSON. It requires complete,
unambiguous generated-record coverage for every reviewed SLO, matching native
inputs, objective/budget agreement, reviewer attestation, and credential-free
sources. Status prints
`slo-rules-engine/sloth-downstream-evidence-status/v1`; fresh evidence exits
zero, while stale source fingerprints exit one with stable findings. Both
commands are local: neither runs Sloth nor reads or mutates a provider. See
[Sloth Downstream Evidence](docs/sloth-downstream-evidence.md).

Cross-check the same reviewed target against Sloth's official main-branch MCP
runtime after the evidence remains fresh:

```bash
bin/rules-ctl sloth-mcp compare \
  --manifest=./managed/checkout-api/sloth/manifest.json \
  --evidence=./work/sloth-evidence/checkout-api.json \
  --endpoint=http://127.0.0.1:8080/mcp \
  --allow-host=127.0.0.1 \
  --expected-version=dev \
  --from=2026-08-01T00:00:00Z \
  --to=2026-08-05T00:00:00Z \
  --output=./work/sloth-mcp/checkout-api.json
```

The command prints and saves the same
`slo-rules-engine/sloth-mcp-comparison/v1` report. `matched` exits zero;
objective, period, list/detail, or budget drift is saved and exits one. Contract
or evidence failures write no report. The endpoint and raw provider text are
never persisted, all six tools must match the pinned read-only schema, and the
report declares `authoritative_status_transport: false`. Continue to use the
evidence-backed `status --provider=sloth` command for the neutral five-state SLO
and error-budget report. See
[Official Sloth MCP Comparison](docs/sloth-mcp-integration.md).

Read the linked Sloth records only after the evidence is fresh:

```bash
bin/rules-ctl status \
  --provider=sloth \
  --manifest=./managed/checkout-api/sloth/manifest.json \
  --evidence=./work/sloth-evidence/checkout-api.json \
  --base-url=http://localhost:9090 \
  --output=./work/checkout-api-sloth-status.json
```

### Inspect live SLO and error-budget status

Read the generated recording-rule series for one reviewed Prometheus Stack
manifest, or use the evidence-linked Sloth form shown above:

```bash
bin/rules-ctl status \
  --provider=prometheus_stack \
  --manifest=./work/generated/checkout-api/prometheus_stack/manifest.json \
  --base-url=http://localhost:9090 \
  --max-age-seconds=300 \
  --output=./work/checkout-api-status.json
```

The command prints and optionally saves the same
`slo-rules-engine/live-slo-status/v1` report. Each SLO is classified as
`healthy`, `at_risk`, `exhausted`, `missing_telemetry`, or `unverifiable` and
includes reviewed identity, owner, dashboard, playbook, objective attainment,
remaining budget, burn windows, source timestamps, freshness, generated
recording-rule identifiers, and query evidence. It performs only Prometheus
`GET /api/v1/query` reads. Operationally unhealthy states still exit zero when
the report was produced; invalid/unreviewed input and unsupported providers
exit nonzero.

Assess every readable target in a current reviewed release bundle:

```bash
bin/rules-ctl status \
  --bundle=./work/release-bundle.json \
  --target-base-url=checkout-api/prometheus_stack=http://localhost:9090 \
  --target-base-url=checkout-api/sloth=http://localhost:9090 \
  --output=./work/release-live-status.json
```

Or define a credential-free `slo-rules-engine/live-status-portfolio/v1` file
whose targets name reviewed manifest paths and whose Sloth targets also name
their current downstream-evidence paths, then pass one
`--target-base-url=service/provider=URL` for every readable target.
Both aggregate modes print `slo-rules-engine/live-slo-status-aggregate/v1`.
Each readable target retains its complete per-manifest report; unsupported
Datadog targets and Sloth targets without evidence remain visible as
`unsupported` coverage rather than being omitted. Bundle schema, identity,
embedded artifacts, review evidence, Sloth evidence/source derivation, and
current source fingerprints plus all runtime mappings are validated before the
first backend read. Runtime URLs are never written into reports or bundles.

### Validate Datadog against an isolated sandbox

Run the credential and dashboard read contract without mutation:

```bash
scripts/datadog-sandbox-smoke
```

In a disposable trial or approved sandbox organization, opt in to one temporary
empty dashboard create/find/delete cycle:

```bash
scripts/datadog-sandbox-smoke --confirm-sandbox-mutation
```

Both modes print public-safe
`slo-rules-engine/datadog-sandbox-smoke/v1` JSON. Read-only mode validates the
key pair, custom-dashboard catalog, and one detail response when available.
Mutation mode additionally verifies the paginated catalog read path,
high-confidence `source_ref` reconciliation, cleanup, and confirmed absence. It
does not create SLOs or monitors and is not a substitute for reviewed
`apply`/`prune`. Setup,
least-privilege scopes, regional `DD_SITE` values, exact reads/writes, and
expected output are in
[Datadog Sandbox Testing](docs/datadog-sandbox-testing.md).

## Provider Model

A provider is a complete operational observability bundle, not an individual artifact writer. It must declare:

- telemetry query binding and reality-check behavior
- SLO and error-budget evaluation artifacts
- burn-rate and missing-telemetry alerts
- contextual routing and decision dashboards
- an automation mode and supported state actions

Current providers:

- `datadog`: `live_api`
- `prometheus_stack`: `manifest_bundle`
- `sloth`: `external_generator`

The initial delivery integration is `notification_router`, which generates contextual route catalog entries without owning notification credentials.

## Safety Boundaries

- Discovery evidence proposes candidates; maintainers accept or reject them.
- Cross-provider evidence reuse never implies automatic metric or query translation.
- Provider generation is deterministic and read-only.
- Neutral SLO intent has an explicit evaluation window, defaulting to `30d`;
  Prometheus Stack uses it for attainment and remaining-budget rules.
- Bundle planning is read-only and rejects stale or invalid predecessors.
- Bundle verification is read-only, requires a valid applied file-backed
  predecessor, and packages fresh managed-file evidence without updating
  journals or invoking Sloth.
- Journal creation accepts exactly one verified dry-run provider plan and never executes it.
- Credentials stay in runtime environment configuration and are forbidden in release bundles.
- Approved plans are credential-free, content-addressed, and limited to one
  Prometheus Stack or Sloth target.
- Confirmed apply and prune require reviewed manifest input.
- Confirmed mutations require durable journal persistence, stop after the first
  failed operation, and verify resulting provider or managed-file state.
- Datadog reconciliation requires managed ownership evidence for risky updates
  or deletes and never persists raw API responses or backend error messages.
- Datadog dashboard reconciliation reads the paginated custom-dashboard catalog
  and full dashboard details; manual dashboard-list membership is not required
  for discovery, import, apply verification, or prune ownership.
- Prometheus Stack and Sloth apply manage deterministic files; downstream deployment remains external.
- Sloth downstream evidence capture is local and credential-free; it requires
  complete reviewed record identity and does not run Sloth or query Prometheus.
- Direct Sloth status requires the exact reviewed manifest, fresh downstream
  evidence, complete SLO coverage, and an explicit Prometheus base URL before
  constructing a provider client.
- Aggregate Sloth status additionally requires exactly one evidence reference
  per readable release or portfolio target; targets without it remain explicit
  coverage gaps.
- Exact file-backed apply rejects changed observed state and same-scope
  concurrency before executing the stored operation list.
- Live status is read-only, requires reviewed manifest provenance, validates
  aggregate inputs and per-target runtime before backend access, and does not
  infer provider queries outside the provider reader.

## Documentation

- [Architecture](docs/design.md)
- [Engineering Use Cases](docs/use-cases.md)
- [Telemetry-First Walkthrough](docs/telemetry-first-walkthrough.md)
- [Prometheus Stack Walkthrough](docs/prometheus-stack-walkthrough.md)
- [Release Bundle Contract](docs/release-bundle-contract.md)
- [Provider State Contract](docs/provider-state-contract.md)
- [Live SLO Status Contract](docs/live-status-contract.md)
- [Sloth Downstream Evidence](docs/sloth-downstream-evidence.md)
- [Official Sloth MCP Comparison](docs/sloth-mcp-integration.md)
- [Datadog Public Contract Evidence](docs/datadog-contract-evidence.md)
- [Datadog Sandbox Testing](docs/datadog-sandbox-testing.md)
- [Provider Contract](docs/provider-contract.md)
- [Provider Contribution Guide](docs/provider-contribution-guide.md)
- [Agent Interface Roadmap](docs/agent-interface-roadmap.md)
- [Implementation Plan](docs/implementation-plan.md)

## Development

```bash
ruby -Ilib test/all_test.rb
scripts/structure-report --check
bin/rules-ctl validate examples/services/checkout.rb
./scripts/verify.sh
```

Run `scripts/structure-report` without `--check` for the deterministic JSON
inventory of code hotspots, command modules, schema contracts, use cases,
boundary coverage, and explicitly allowlisted dependency debt.

No external Ruby dependencies are required.
