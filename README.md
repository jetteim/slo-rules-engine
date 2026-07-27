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
- compare reviewed desired state with existing backend or managed-file state
- persist a deterministic operation journal from one verified dry-run provider plan
- apply or prune reviewed artifacts through explicit confirmed workflows
- run telemetry reality checks before treating an SLO as operationally ready
- validate Datadog credentials and dashboard reconciliation in an isolated
  sandbox before relying on live provider behavior

The detailed commands, expected files, and safety boundaries are in [Engineering Use Cases](docs/use-cases.md).

## Provider Outputs

| Provider | Generation output | Dry-run planning output | Confirmed state output |
| --- | --- | --- | --- |
| `datadog` | Reviewed manifest containing SLOs, burn-rate monitors, missing-telemetry monitors, dashboards, and route context | Versioned desired/observed state plus API-oriented `create`, `update`, `recreate`, or `noop` operations with ownership evidence and provider risk | Datadog resources, durable operation journal, and a `ProviderStateResult` with backend identity and canonical payload/absence verification |
| `prometheus_stack` | Reviewed manifest containing recording rules, burn-rate and telemetry-gap alerts, Grafana dashboards, and Alertmanager route intent | Versioned desired/observed state plus `write` or `noop` operations for the manifest and every native bundle file | Managed JSON/YAML files, durable operation journal, and a `ProviderStateResult` with post-write/delete convergence evidence |
| `sloth` | Reviewed manifest containing Sloth `prometheus/v1` SLO specs | Versioned desired/observed state plus `write` or `noop` operations for the manifest and native Sloth input, and an external-generator handoff | Verified engine-owned manifest/input files, durable journal/result, and a skipped external handoff that remains pending and operator-owned |

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
  --output=./work/artifact-index.json \
  ./work/discovery/index.json

bin/rules-ctl bundle create \
  --artifact-index=./work/artifact-index.json \
  --reviewer=team/payments-sre \
  --reviewed-at=2026-07-26T09:30:00Z \
  --output=./work/review-ready.json

bin/rules-ctl bundle plan ./work/review-ready.json \
  --target-output=checkout-api/prometheus_stack=./managed \
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

Approval writes a content-addressed artifact containing the selected target,
review attestation, bundle lineage, manifest/review/handoff fingerprints, exact
dry-run provider plan, and managed output directory. Apply first rechecks the
managed-file plan fingerprint. Drift returns `stale_approved_plan` before a
journal or provider mutation; a concurrent apply for the same scope returns
`approved_plan_scope_busy`. Successful stdout contains the live
`ProviderStateResult`, the approved-plan reference, and the durable journal
path. The journal preserves both the live execution-plan identity and the
approved dry-run plan identity.

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
remains pending. Automatic resume and exact-plan replay are not implemented;
exact execution is available through the separate approved-plan workflow above.

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
- Bundle planning is read-only and rejects stale or invalid predecessors.
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
- Exact file-backed apply rejects changed observed state and same-scope
  concurrency before executing the stored operation list.

## Documentation

- [Engineering Use Cases](docs/use-cases.md)
- [Telemetry-First Walkthrough](docs/telemetry-first-walkthrough.md)
- [Prometheus Stack Walkthrough](docs/prometheus-stack-walkthrough.md)
- [Release Bundle Contract](docs/release-bundle-contract.md)
- [Provider State Contract](docs/provider-state-contract.md)
- [Datadog Public Contract Evidence](docs/datadog-contract-evidence.md)
- [Datadog Sandbox Testing](docs/datadog-sandbox-testing.md)
- [Provider Contract](docs/provider-contract.md)
- [Provider Contribution Guide](docs/provider-contribution-guide.md)
- [Implementation Plan](docs/implementation-plan.md)

## Development

```bash
ruby -Ilib test/all_test.rb
bin/rules-ctl validate examples/services/checkout.rb
./scripts/verify.sh
```

No external Ruby dependencies are required.
