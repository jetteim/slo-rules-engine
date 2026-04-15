# SLO Rules Engine

Open-source SLI/SLO rules engine with a Ruby DSL, backend-neutral reliability intent, provider-based artifact generation, telemetry lookup, telemetry reality checks, provider apply planning, and contextual alert routing.

The project keeps the useful shape of an SRE rules DSL while removing organization-specific platform assumptions. Providers are complete observability backend bundles, not individual tools.

## Goals

- Keep a concise Ruby DSL for service level definitions.
- Convert DSL definitions into neutral service reliability intent.
- Generate SLOs, alert rules, notification routing, and dashboards through providers.
- Support reality checks against measured telemetry.
- Generate candidate SLIs/SLOs from existing telemetry during onboarding.
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

- `datadog`: Datadog SLOs, monitors, dashboards, route references, query validation, and live API apply support.
- `prometheus_stack`: Prometheus-compatible recording/alert rules, Alertmanager routing, Grafana dashboards, PromQL reality checks, and manifest-bundle apply support.
- `sloth`: Sloth `prometheus/v1` SLO specs for Prometheus rule generation and external-generator apply handoff.
Initial integration:

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
bin/rules-ctl generate --provider prometheus_stack --output-dir ./generated examples/services/checkout.rb
bin/rules-ctl generate-routes --integration notification_router examples/services/checkout.rb
# Returns candidate SLIs/SLOs plus findings for rejected or incomplete telemetry.
bin/rules-ctl candidates examples/telemetry/checkout-signals.json
bin/rules-ctl recommend-calculation-basis --observations-per-second=25 --failed-observations-to-alert=120
bin/rules-ctl reality-check --provider datadog --telemetry examples/telemetry/checkout-signals.json examples/services/checkout.rb
bin/rules-ctl apply --provider datadog --dry-run examples/services/checkout.rb
bin/rules-ctl apply --provider prometheus_stack --dry-run --output-dir ./generated examples/services/checkout.rb
bin/rules-ctl apply --provider sloth --dry-run --output-dir ./generated examples/services/checkout.rb
bin/rules-ctl migration-report path/to/legacy/service-definition.rb
bin/rules-ctl model-report examples/services/checkout.rb
bin/rules-ctl providers list
bin/rules-ctl integrations list
```

## Development

```bash
ruby -Ilib test/all_test.rb
bin/rules-ctl validate examples/services/checkout.rb
scripts/verify.sh
```

Provider contributors should start with the [Provider Contribution Guide](docs/provider-contribution-guide.md) and the [Provider Contract](docs/provider-contract.md).

No external Ruby dependencies are required for the initial skeleton.
