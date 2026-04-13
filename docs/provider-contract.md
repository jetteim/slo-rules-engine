# Provider Contract

A provider is a complete SLO observability backend bundle.

It may be implemented by one product or several coordinated tools. The core engine treats both as one provider when they jointly satisfy the operational contract.

## Required Capabilities

Every production-grade provider should declare support for:

- `sli_query_binding`
- `slo_evaluation`
- `burn_rate_alerting`
- `missing_telemetry_detection`
- `contextual_alerts`
- `notification_router_integration`
- `parameterized_dashboards`
- `reality_check`

Optional capabilities:

- `apply`
- `prune`
- `import_existing`
- `cost_estimation`

## Provider Responsibilities

Providers receive neutral intent and return generated artifacts.

They must not mutate DSL objects. They should report unsupported intent through validation errors instead of silently dropping behavior.

## Initial Providers

### `datadog`

Single-tool provider.

Expected artifacts:

- SLO definitions
- monitors
- dashboards
- webhook integration payloads or route references
- query validation requests

### `prometheus_stack`

Multi-tool provider treated as one backend bundle.

Expected artifacts:

- Prometheus-compatible recording rules
- Prometheus-compatible alert rules
- Alertmanager routing labels and webhook route references
- Grafana dashboards
- PromQL reality-check queries

## Delivery Integrations

Delivery integrations are not providers. They do not evaluate SLIs/SLOs or own dashboards.

They receive contextual alert route intent from providers.

### `notification_router`

Route catalog integration for contextual alert delivery.

Expected artifacts:

- Datadog route entries
- Alertmanager route entries
- route availability check manifests

The notification router owns delivery to Teams, Slack, Telegram, webhook, console, or other channels. The rules engine only generates route intent and integration keys.
