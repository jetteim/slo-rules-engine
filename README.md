# SLO Rules Engine

Open-source SLI/SLO rules engine with a Ruby DSL, backend-neutral reliability intent, provider-based artifact generation, telemetry reality checks, and contextual alert routing.

The project keeps the useful shape of an SRE rules DSL while removing organization-specific platform assumptions. Providers are complete observability backend bundles, not individual tools.

## Goals

- Keep a concise Ruby DSL for service level definitions.
- Convert DSL definitions into neutral service reliability intent.
- Generate SLOs, alert rules, notification routing, and dashboards through providers.
- Support reality checks against measured telemetry.
- Generate candidate SLIs/SLOs from existing telemetry during onboarding.
- Keep the project public-safe: no organization names, internal domains, private services, or proprietary platform assumptions.

## Provider Model

A provider must be capable of fueling SLI/SLO operation end to end:

- bind SLIs to telemetry queries
- evaluate SLOs and error budgets
- emit burn-rate and missing-telemetry alerts
- send contextual alerts through a notification route
- provide parameterized decision dashboards
- optionally validate current telemetry and apply/prune generated resources

Initial providers:

- `datadog`: Datadog SLOs, monitors, dashboards, webhooks, and query validation.
- `prometheus_stack`: Prometheus-compatible recording/alert rules, Alertmanager routing, Grafana dashboards, and PromQL reality checks.
Initial integration:

- `notification_router`: generated route catalog entries for contextual alert delivery used by backend providers.

Future provider candidates:

- `grafana_cloud`
- `openslo`
- `sloth`
- `pyrra`
- `nobl9`
- `perses`
- `newrelic`
- `honeycomb`
- `chronosphere`
- `terraform`
- `kubernetes_custom_resources`

## Early CLI Target

```bash
bin/rules-ctl validate examples/services/checkout.rb
bin/rules-ctl generate --provider datadog examples/services/checkout.rb
bin/rules-ctl generate --provider prometheus_stack examples/services/checkout.rb
bin/rules-ctl generate-routes --integration notification_router examples/services/checkout.rb
bin/rules-ctl candidates examples/telemetry/checkout-signals.json
bin/rules-ctl recommend-calculation-basis --observations-per-second=25 --failed-observations-to-alert=120
bin/rules-ctl providers list
bin/rules-ctl integrations list
```

## Development

```bash
ruby -Ilib test/all_test.rb
bin/rules-ctl validate examples/services/checkout.rb
```

No external Ruby dependencies are required for the initial skeleton.
