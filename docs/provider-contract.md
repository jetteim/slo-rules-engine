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

Provider generation is a transform and must stay deterministic. Provider apply is a sink and must be isolated behind dry-run, confirmation, and provider-specific state-action support. Generated manifests and reviewed manifest inputs must validate against provider schema before diff, apply, import, or prune.

## Telemetry Evidence Contract

Providers may support explicit metric lookup, service-scoped discovery, or both.

When telemetry evidence is supported:

- `lookup-telemetry` returns normalized evidence for one explicit metric or query.
- `discover-telemetry` returns normalized evidence for a documented service, selector, host, or backend-specific scope.
- results must normalize to `provider`, `signals`, and `findings` so onboarding and reality-check flows can reuse them without backend-specific parsing.
- unsupported scopes or filters must fail explicitly.
- provider-specific scope limits must be documented.

Discovery is evidence for review, not automatic SLO policy. Candidate generation and `draft-definition` consume normalized `signals`; backend-specific payload details stay inside provider adapters.

## Provider Responsibilities

Providers receive neutral intent and return generated artifacts.

They must not mutate DSL objects. They should report unsupported intent through validation errors instead of silently dropping behavior.

Providers are downstream translators, not reliability policy owners. Objective selection, calculation-basis choice, miss-policy, and alert intent belong to the neutral model and review workflow. Provider contributions should follow the provider contribution stream in [Evolution Plan](evolution-plan.md) and the [Provider Contribution Guide](provider-contribution-guide.md).

Do not use provider code to invent reliability policy. A provider may express reviewed intent in backend syntax, but it must not decide what the service should promise or when responders should be paged.

Providers receive reliability intent as input. They may render miss-policy, measurement caveats, playbook links, and dashboard variables into backend-specific artifacts, but objective selection and calculation-basis policy remain model decisions.

Generation must not mutate live systems. Backend state changes must use explicit apply commands. Dry-run plans must be available before live mutation. Live mutation must require confirmation and must not store credentials.

Provider contributors must extend schema validation for every new artifact collection they introduce. Reviewed manifest compatibility is part of the provider contract, not optional helper logic.

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
- retry handling for rate limiting and transient server errors, including Datadog `X-RateLimit-Reset` and `X-RateLimit-Period` headers
- source-artifact provenance through managed `source_ref` tags used during import, diff, apply, and prune
- managed identity tags required on apply-ready payloads: `managed_by:slo-rules-engine`, `service:*`, and `source_ref:*`
- monitor payloads also require `route_key:*` tags for alert-routing context
- SLO payloads require `30d` timeframe consistency between `timeframe`, `thresholds[0].timeframe`, and `target_threshold`
- reviewed counter-ratio `time_slice` SLOs must translate to Datadog `sli_specification.time_slice` payloads with explicit comparator, query interval, threshold, and formula/query structure
- reviewed threshold-based `time_slice` SLOs must translate reviewed `success_threshold` operators and values into Datadog comparators, numeric thresholds, and provider-query expressions merged with reviewed selector scope
- burn-rate monitor payloads require the Datadog `burn_rate(...).over("30d")...` query shape and `options.thresholds.critical` must match the query threshold
- telemetry-gap monitor payloads require the `avg(last_10m):... < 0` no-data query shape with `notify_no_data: true`, `no_data_timeframe: 10`, and `critical: 0`
- reconciliation compares provider-owned tags and ignores unmanaged backend tags; provider-schema conformance must still be verified before production use

Expected telemetry behavior:

- explicit metric lookup through Datadog query APIs
- service/tag-filter discovery or host-scoped discovery through the active metrics API
- host scope must not be combined with tag-filter discovery in one request

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

Expected telemetry behavior:

- explicit metric lookup through Prometheus-compatible series and query APIs
- service or selector-scoped discovery through metric-name label values
- normalized lookup output reusable by onboarding and reality-check flows

### `sloth`

Prometheus-oriented provider that emits Sloth `prometheus/v1` SLO specs for Sloth rule generation.

Automation mode: `external_generator`.

Expected artifacts:

- Sloth SLO spec files
- Prometheus event queries
- page and ticket alert context labels
- annotations carrying reviewed reliability intent

The Sloth provider does not execute the Sloth CLI or apply generated rules. It produces reviewable spec artifacts and an external-generator handoff plan.

Expected telemetry behavior:

- reuse the Prometheus-compatible lookup and discovery baseline for onboarding and sanity checks

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
