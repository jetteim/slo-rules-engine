# SLO Rules Engine

Open-source SLI/SLO rules engine with a Ruby DSL, backend-neutral reliability intent, provider-based artifact generation, telemetry discovery and lookup, telemetry reality checks, provider apply planning, and contextual alert routing.

The project keeps the useful shape of an SRE rules DSL while removing organization-specific platform assumptions. Providers are complete observability backend bundles, not individual tools.

## Goals

- Keep a concise Ruby DSL for service level definitions.
- Convert DSL definitions into neutral service reliability intent.
- Generate SLOs, alert rules, dashboards, and delivery integration route catalogs from reviewed reliability intent.
- Support reality checks against measured telemetry.
- Generate candidate SLIs/SLOs from existing telemetry during onboarding, starting from checked-in inventories or provider discovery output.
- Manage generated backend state through explicit dry-run and apply workflows.
- Keep the project public-safe: no organization names, internal domains, private services, or proprietary platform assumptions.

## Provider Model

A provider must be capable of fueling SLI/SLO operation end to end:

- bind SLIs to telemetry queries
- evaluate SLOs and error budgets
- emit burn-rate and missing-telemetry alerts
- send contextual alerts through a notification route
- provide parameterized decision dashboards
- declare an automation mode for apply planning and backend state management
- optionally validate current telemetry and apply/prune generated resources through explicit commands

Initial providers:

- `datadog`: Datadog metric SLOs, counter-ratio and threshold-based time-slice SLOs, monitors, dashboards, route references, query validation, source-tagged state reconciliation, and live API apply support.
- `prometheus_stack`: Prometheus-compatible recording/alert rules, Alertmanager routing, Grafana dashboards, PromQL reality checks, and manifest-bundle apply support.
- `sloth`: Sloth `prometheus/v1` SLO specs for Prometheus rule generation and external-generator apply handoff.

Initial delivery integration:

- `notification_router`: generated route catalog entries for contextual alert delivery used by backend providers.

Future provider candidates:

- `grafana_cloud`
- `pyrra`
- `nobl9`
- `perses`
- `newrelic`
- `honeycomb`
- `chronosphere`
- `terraform`
- `kubernetes_custom_resources`

Future interchange/export candidates:

- `openslo`

## Early CLI Target

```bash
bin/rules-ctl validate examples/services/checkout.rb
bin/rules-ctl generate --provider datadog examples/services/checkout.rb
bin/rules-ctl generate --provider prometheus_stack examples/services/checkout.rb
bin/rules-ctl generate --provider sloth examples/services/checkout.rb
bin/rules-ctl generate --provider prometheus_stack --output-dir ./generated --handoff-dir ./handoff examples/services/checkout.rb
bin/rules-ctl manifest-review --provider datadog examples/services/checkout.rb
bin/rules-ctl manifest-review --provider datadog --manifest ./generated/checkout-api/datadog/manifest.json --handoff-dir ./handoff --output ./generated/reviews/datadog.json
bin/rules-ctl manifest-review --provider datadog --manifest ./generated/checkout-api/datadog/manifest.json --handoff-dir ./handoff --report ./generated/reviews/datadog.json
bin/rules-ctl generate-routes --integration notification_router examples/services/checkout.rb
# Returns candidate SLIs/SLOs plus findings for rejected or incomplete telemetry.
bin/rules-ctl candidates examples/telemetry/checkout-signals.json
# Discovery inventories active metrics by service or host scope before candidate review.
bin/rules-ctl discover-telemetry --provider datadog --service checkout-api
bin/rules-ctl discover-telemetry --provider datadog --host checkout-host
bin/rules-ctl discover-telemetry --provider prometheus_stack --service checkout-api --base-url http://localhost:9090
bin/rules-ctl discover-telemetry --provider datadog --scope-file ./examples/telemetry/scopes.json --output-dir ./discovery
bin/rules-ctl onboarding-summary --handoff-dir ./handoff ./discovery/index.json
bin/rules-ctl onboarding-artifact-index --handoff-dir ./handoff --draft-dir ./drafts --manifest-dir ./generated --provider datadog --output ./handoff/artifact-index.json ./discovery/index.json
bin/rules-ctl review-handoff --accept=request-latency --reject=request-traffic --note='Latency accepted for draft generation.' ./handoff/checkout-prod.handoff.json
bin/rules-ctl validate-handoff ./handoff/checkout-prod.handoff.json
bin/rules-ctl draft-from-handoff --service checkout-api --owner payments-platform ./handoff/checkout-prod.handoff.json
bin/rules-ctl lookup-telemetry --provider datadog --metric http.server.request.duration --kind latency --query 'p95:http.server.request.duration{service:checkout-api}'
bin/rules-ctl lookup-telemetry --provider prometheus_stack --metric http_server_request_duration_seconds_count --kind errors --base-url http://localhost:9090
bin/rules-ctl candidates examples/telemetry/checkout-lookup-result.json
bin/rules-ctl draft-definition --service checkout-api --owner payments-platform examples/telemetry/checkout-lookup-result.json
bin/rules-ctl recommend-calculation-basis --observations-per-second=25 --failed-observations-to-alert=120
bin/rules-ctl reality-check --provider datadog --telemetry examples/telemetry/checkout-signals.json examples/services/checkout.rb
bin/rules-ctl reality-check --provider datadog --lookup-result examples/telemetry/checkout-lookup-result.json examples/services/checkout.rb
bin/rules-ctl reality-check --provider datadog --online examples/services/checkout.rb
bin/rules-ctl apply --provider datadog --dry-run examples/services/checkout.rb
bin/rules-ctl apply --provider datadog --dry-run --manifest ./generated/checkout-api/datadog/manifest.json
bin/rules-ctl diff --provider datadog --manifest ./generated/checkout-api/datadog/manifest.json
bin/rules-ctl import --provider datadog --manifest ./generated/checkout-api/datadog/manifest.json
bin/rules-ctl prune --provider datadog --dry-run --manifest ./generated/checkout-api/datadog/manifest.json
bin/rules-ctl apply --provider prometheus_stack --dry-run --output-dir ./generated examples/services/checkout.rb
bin/rules-ctl apply --provider prometheus_stack --confirm --output-dir ./managed --manifest ./generated/checkout-api/prometheus_stack/manifest.json --handoff-dir ./handoff --review-report ./generated/manifest-review/prometheus_stack.json
bin/rules-ctl diff --provider prometheus_stack --output-dir ./managed --manifest ./generated/checkout-api/prometheus_stack/manifest.json
bin/rules-ctl import --provider prometheus_stack --output-dir ./managed --manifest ./generated/checkout-api/prometheus_stack/manifest.json
bin/rules-ctl prune --provider prometheus_stack --confirm --output-dir ./managed --manifest ./generated/checkout-api/prometheus_stack/manifest.json --handoff-dir ./handoff --review-report ./generated/manifest-review/prometheus_stack.json
bin/rules-ctl apply --provider sloth --dry-run --output-dir ./generated examples/services/checkout.rb
bin/rules-ctl apply --provider sloth --confirm --output-dir ./managed --manifest ./generated/checkout-api/sloth/manifest.json
bin/rules-ctl diff --provider sloth --output-dir ./managed --manifest ./generated/checkout-api/sloth/manifest.json
bin/rules-ctl import --provider sloth --output-dir ./managed --manifest ./generated/checkout-api/sloth/manifest.json
bin/rules-ctl prune --provider sloth --confirm --output-dir ./managed --manifest ./generated/checkout-api/sloth/manifest.json
bin/rules-ctl model-report examples/services/checkout.rb
bin/rules-ctl providers list
bin/rules-ctl integrations list
```

The `candidates` and `draft-definition` commands accept either a raw telemetry signal array or a normalized provider evidence envelope with `provider`, `signals`, and `findings`.
Batch `discover-telemetry --scope-file` writes one normalized evidence file per scope plus an aggregate `index.json` for later review-readiness ranking and draft generation.
The `onboarding-summary --handoff-dir` command writes per-scope handoff packets, and `review-handoff` records accepted or rejected candidate decisions without changing saved discovery or candidate evidence.
Rerunning `onboarding-summary --handoff-dir` preserves reviewed handoff decisions and exposes review summaries plus reviewed provenance in the summary output.
The `onboarding-artifact-index` command ties saved discovery results, handoff packets, reviewed draft files, provider manifests, and manifest-review reports into one compact handoff index with per-scope missing-artifact findings.
The `validate-handoff` command checks reviewed packets before handoff, and `draft-from-handoff` emits a Ruby DSL draft from accepted handoff candidates without rerunning backend discovery.
The `model-report` command includes reviewed handoff provenance from DSL definitions so reviewers can see accepted onboarding context before provider generation.
The `manifest-review` command reports provider manifest review readiness, including missing, incomplete, or stale reviewed provenance, handoff packet navigation, deterministic freshness fingerprints, saved report freshness validation with `--report`, explicit saved report output, and queue-level review status rollups.
When `generate --output-dir` is used, the engine also writes `manifest-review/<provider>.json` next to generated provider manifests.
Confirmed `apply` and `prune` with `--handoff-dir` require current reviewed handoff evidence before mutation, and `--review-report` requires the saved manifest-review report to match current manifest and handoff fingerprints.
Live `apply --confirm --manifest` requires reviewed handoff provenance in every manifest before provider mutation or file-backed apply.

Confirmed `apply` now requires `--manifest` so live state changes always use reviewed provider artifacts instead of regenerating definitions inline.
Confirmed `prune` now requires `--manifest` so destructive state removal is also tied to reviewed provider artifacts.
The `apply` command accepts either definition files or a reviewed provider manifest through `--manifest`.
The `diff` command accepts the same reviewed manifest input and compares desired artifacts to observed provider state before mutation.
The `import` and `prune` commands accept the same reviewed manifest input; Datadog prune treats already-missing resources as success.

## Development

```bash
ruby -Ilib test/all_test.rb
bin/rules-ctl validate examples/services/checkout.rb
scripts/verify.sh
```

Provider contributors should start with the [Provider Contribution Guide](docs/provider-contribution-guide.md) and the [Provider Contract](docs/provider-contract.md).
Teams planning telemetry-first rollout should start with the [Telemetry-First Adoption Map](docs/adoption-map.md).
The full saved-artifact onboarding path is documented in the [Telemetry-First Walkthrough](docs/telemetry-first-walkthrough.md).

No external Ruby dependencies are required for the initial skeleton.
