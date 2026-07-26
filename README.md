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
- compare reviewed desired state with existing backend or managed-file state
- apply or prune reviewed artifacts through explicit confirmed workflows
- run telemetry reality checks before treating an SLO as operationally ready

The detailed commands, expected files, and safety boundaries are in [Engineering Use Cases](docs/use-cases.md).

## Provider Outputs

| Provider | Generation output | Dry-run planning output | Confirmed state output |
| --- | --- | --- | --- |
| `datadog` | Reviewed manifest containing SLOs, burn-rate monitors, missing-telemetry monitors, dashboards, and route context | API-oriented `create`, `update`, `recreate`, or `noop` operations with ownership evidence and provider risk | Datadog SLO, monitor, and dashboard resources through the live API |
| `prometheus_stack` | Reviewed manifest containing recording rules, burn-rate and telemetry-gap alerts, Grafana dashboards, and Alertmanager route intent | `write` or `noop` operations for the manifest and every native bundle file | `manifest.json`, Prometheus Operator `PrometheusRule` YAML, Grafana dashboard `ConfigMap` YAML, and Alertmanager route-intent YAML |
| `sloth` | Reviewed manifest containing Sloth `prometheus/v1` SLO specs | `write` or `noop` operations for the manifest and native Sloth input, plus an external-generator handoff | `manifest.json` and native Sloth YAML input; the engine does not run Sloth or mutate Prometheus |

All providers also emit a saved provider-level manifest-review report when `generate --output-dir` is used.

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
  --manifest=./work/generated/checkout-api/prometheus_stack/manifest.json \
  --handoff-dir=./work/handoff \
  --review-report=./work/generated/manifest-review/prometheus_stack.json
```

`diff`, `import`, and dry-run planning are observational. Confirmed `apply` and `prune` are the mutation boundaries and require reviewed manifests; current handoff and report evidence can be required as additional gates.

### Check whether the SLO is supported by real telemetry

```bash
bin/rules-ctl reality-check \
  --provider=prometheus_stack \
  --online \
  --base-url=http://localhost:9090 \
  ./work/checkout-api.rb
```

The report identifies missing metrics, absent series, incomplete histogram evidence, and other provider-binding gaps. It does not silently adjust the reviewed objective or calculation basis.

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
- Credentials stay in runtime environment configuration and are forbidden in release bundles.
- Confirmed apply and prune require reviewed manifest input.
- Datadog reconciliation requires managed ownership evidence for risky updates or deletes.
- Prometheus Stack and Sloth apply manage deterministic files; downstream deployment remains external.

## Documentation

- [Engineering Use Cases](docs/use-cases.md)
- [Telemetry-First Walkthrough](docs/telemetry-first-walkthrough.md)
- [Prometheus Stack Walkthrough](docs/prometheus-stack-walkthrough.md)
- [Release Bundle Contract](docs/release-bundle-contract.md)
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
