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
- `apply_plan`

Optional capabilities:

- `apply`
- `prune`
- `import_existing`
- `cost_estimation`

## Automation Modes

Every provider must declare one automation mode:

- `live_api`: the provider can reconcile generated artifacts with a backend API.
- `manifest_bundle`: the provider manages deterministic files for a deployment system.
- `external_generator`: the provider emits input for another tool that expands or applies backend resources.
- `manifest_only`: the provider can generate artifacts but cannot participate in apply planning yet.

Every provider must also declare supported state actions:

- `plan`
- `apply`
- `diff`
- `import_existing`
- `prune`

Unsupported actions must fail with explicit provider validation output.

## State Pipeline Contract

Provider state management follows a pipeline contract:

- **Sources:** neutral service definitions, generated manifests, telemetry lookup results, and imported backend state.
- **Transforms:** provider validation, telemetry sanity checks, candidate generation, and apply-plan calculation.
- **Sinks:** live backend APIs, manifest bundles, external generator handoffs, and route catalogs.
- **Findings:** unsupported fields, missing telemetry, missing backend state, unsafe mutation, and unavailable provider actions.

Provider generation is a transform and must stay deterministic. Provider apply is a sink and must be isolated behind dry-run, confirmation, and provider-specific state-action support.

## Provider Responsibilities

Providers receive neutral intent and return generated artifacts.

They must not mutate DSL objects. They should report unsupported intent through validation errors instead of silently dropping behavior.

Providers are downstream translators, not reliability policy owners. Objective selection, calculation-basis choice, miss-policy, and alert intent belong to the neutral model and review workflow. Provider contributions should follow the provider contribution stream in [Evolution Plan](evolution-plan.md) and the [Provider Contribution Guide](provider-contribution-guide.md).

Do not use provider code to invent reliability policy. A provider may express reviewed intent in backend syntax, but it must not decide what the service should promise or when responders should be paged.

Providers receive reliability intent as input. They may render miss-policy, measurement caveats, playbook links, and dashboard variables into backend-specific artifacts, but objective selection and calculation-basis policy remain model decisions.

Generation must not mutate live systems. Backend state changes must use explicit apply commands. Dry-run plans must be available before live mutation. Live mutation must require confirmation and must not store credentials.

## Initial Providers

### `datadog`

Single-tool provider.

Automation mode: `live_api`.

Expected artifacts:

- SLO definitions
- monitors
- dashboards
- webhook integration payloads or route references
- query validation requests

Expected state behavior:

- dry-run apply plan
- live API apply when confirmed
- credential validation through environment or explicit runtime configuration
- retry handling for rate limiting and transient server errors

### `prometheus_stack`

Multi-tool provider treated as one backend bundle.

Automation mode: `manifest_bundle`.

Expected artifacts:

- Prometheus-compatible recording rules
- Prometheus-compatible alert rules
- Alertmanager routing labels and webhook route references
- Grafana dashboards
- PromQL reality-check queries

Expected state behavior:

- dry-run manifest write plan
- confirmed file write into an output directory
- direct backend mutation only through a future dedicated adapter

### `sloth`

Prometheus-oriented provider that emits Sloth `prometheus/v1` SLO specs for Sloth rule generation.

Automation mode: `external_generator`.

Expected artifacts:

- Sloth SLO spec files
- Prometheus event queries
- page and ticket alert context labels
- annotations carrying reviewed reliability intent

The Sloth provider does not execute the Sloth CLI or apply generated rules. It produces reviewable spec artifacts and an external-generator handoff plan.

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
