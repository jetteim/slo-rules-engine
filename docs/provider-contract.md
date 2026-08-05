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

Plan and import output also carries the versioned [Provider State Contract](provider-state-contract.md). The shared contract standardizes desired state, observed state, changes, findings, and fingerprints while preserving provider-owned payloads, identifiers, ownership evidence, and risk.

## Telemetry Evidence Contract

Providers may support explicit metric lookup, service-scoped discovery, or both.

When telemetry evidence is supported:

- `lookup-telemetry` returns normalized evidence for one explicit metric or query.
- `discover-telemetry` returns normalized evidence for a documented service, selector, host, or backend-specific scope.
- `discover-telemetry --scope-file` may orchestrate repeated provider `discover(...)` calls for one provider run and must preserve the same normalized evidence shape in each saved per-scope result file.
- results must normalize to `provider`, `signals`, and `findings` so onboarding and reality-check flows can reuse them without backend-specific parsing.
- saved batch-discovery evidence must remain reusable by later onboarding stages without provider-specific transformation.
- unsupported scopes or filters must fail explicitly.
- provider-specific scope limits must be documented.
- providers that support discovery must document whether they support the shared batch CLI contract and what scope combinations are valid in that mode.

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
- versioned provider-state plan/import evidence with reviewed desired-state and current backend-state fingerprints
- managed identity tags required on apply-ready payloads: `managed_by:slo-rules-engine`, `service:*`, and `source_ref:*`
- monitor payloads also require `route_key:*` tags for alert-routing context
- SLO payloads require `30d` timeframe consistency between `timeframe`, `thresholds[0].timeframe`, and `target_threshold`
- reviewed counter-ratio `time_slice` SLOs must translate to Datadog `sli_specification.time_slice` payloads with explicit comparator, query interval, threshold, and formula/query structure
- reviewed threshold-based `time_slice` SLOs must translate reviewed `success_threshold` operators and values into Datadog comparators, numeric thresholds, and provider-query expressions merged with reviewed selector scope
- when explicit Datadog query text is absent, reviewed threshold-based counter, distribution, and gauge bindings must still be translatable from metric type, selector scope, operator, and reviewed objective/threshold inputs
- generated Datadog dashboard evidence queries must merge reviewed selector scope into provider query expressions so dashboard drill-down remains aligned with the reviewed SLI instance
- generated Datadog dashboards must validate the expected template-variable set and the generated note/timeseries widget structure before live mutation
- burn-rate monitor payloads require the Datadog `burn_rate(...).over("30d")...` query shape and `options.thresholds.critical` must match the query threshold
- telemetry-gap monitor payloads require the `avg(last_10m):... < 0` no-data query shape with `notify_no_data: true`, `no_data_timeframe: 10`, and `critical: 0`
- reconciliation compares provider-owned tags and ignores unmanaged backend tags; provider-schema conformance must still be verified before production use

Expected telemetry behavior:

- explicit metric lookup through Datadog query APIs
- service/tag-filter discovery or host-scoped discovery through the active metrics API
- host scope must not be combined with tag-filter discovery in one request
- batch discovery through `discover-telemetry --scope-file` with one saved normalized evidence file per scope and one aggregate `index.json`

### `prometheus_stack`

Multi-tool provider treated as one backend bundle.

Automation mode: `manifest_bundle`.

Expected artifacts:

- one base Prometheus-compatible observation recording rule per SLI instance
- derived evaluation-window success-ratio, error-ratio, objective-ratio, error-budget-ratio, and error-budget-remaining-ratio recording rules per SLO
- SLO-specific burn-rate recording rules
- Prometheus-compatible alert rules
- Alertmanager routing labels and webhook route references
- Grafana dashboards
- PromQL reality-check queries

Expected state behavior:

- dry-run plans the reviewed manifest, PrometheusRule, Grafana dashboard ConfigMap, and Alertmanager route-intent files
- confirmed file apply validates and writes the complete deterministic bundle into an output directory
- diff compares every managed file, import reports missing native files, and prune covers the complete bundle
- the Alertmanager route-intent file records notification-router matcher and webhook-path requirements without claiming receiver endpoint or credential ownership
- versioned provider-state plan/import evidence covering the manifest and every native bundle file
- direct backend mutation only through a future dedicated adapter

Recording-rule behavior:

- record names must satisfy the Prometheus metric-name contract even when neutral service, SLI, instance, or SLO identifiers contain hyphens
- SLI observation rules must not be duplicated when one SLI instance has multiple SLOs
- reviewed SLO identity remains in labels and derived series
- the reviewed evaluation window remains in SLO labels and controls objective-attainment and remaining-budget evaluation
- burn-rate records calculate over their own policy windows instead of reusing the long-window attainment ratio
- threshold SLOs must use numeric thresholds and `time_slice` calculation basis
- unsupported threshold semantics must fail provider validation instead of producing a non-ratio series named as a success ratio

Expected telemetry behavior:

- explicit metric lookup through Prometheus-compatible series and query APIs
- service or selector-scoped discovery through metric-name label values
- normalized lookup output reusable by onboarding and reality-check flows
- batch discovery through `discover-telemetry --scope-file` for service and selector scopes
- reviewed one-manifest live status through GET-only instant queries of generated recording-rule identifiers
- live status normalizes provider evidence into objective attainment, remaining budget, burn windows, source freshness, and stable findings without moving PromQL into the neutral model

Additional capability:

- `live_slo_status` indicates that a provider has an implemented live-status
  reader; it is declared by `prometheus_stack` and by `sloth` when direct reads
  are linked to fresh reviewed downstream evidence

### `sloth`

Prometheus-oriented provider that emits Sloth `prometheus/v1` SLO specs for Sloth rule generation.

Automation mode: `external_generator`.

Expected artifacts:

- Sloth SLO spec files
- Prometheus event queries
- page and ticket alert context labels
- annotations carrying reviewed reliability intent
- optional `slo-rules-engine/sloth-downstream-evidence/v1` reviewer evidence
  linking current native input to saved generated Prometheus rules

The Sloth provider does not execute the Sloth CLI or apply generated rules. It produces reviewable spec artifacts and an external-generator handoff plan.

Expected state behavior:

- dry-run plans include the reviewed engine manifest, native Sloth spec input files, and the external-generator handoff command
- confirmed file apply writes the engine manifest plus deterministic Sloth `prometheus/v1` YAML input files under the provider output directory
- diff and prune account for both the engine manifest and generated Sloth input files
- import reads the engine manifest and every expected native Sloth input and reports missing external-generator inputs
- versioned provider-state plan/import evidence preserves native input state and external handoff intent
- external-generator handoff commands point at the native Sloth spec files while retaining the reviewed engine manifest as provenance
- no live backend mutation or Sloth CLI execution happens inside the engine
- downstream evidence capture requires exact canonical manifest/native-input
  parity, complete unambiguous record mappings for every reviewed SLO,
  objective/budget agreement, reviewer attestation, and credential-free inputs
- downstream evidence status validates content identity before rereading every
  local source fingerprint; neither command makes a provider call
- direct live status requires the exact reviewed manifest, fresh complete
  downstream evidence, and an explicit Prometheus runtime before client
  construction; it queries only evidence-declared bindings
- the official Sloth main-branch MCP server is a planned optional read-only
  provider adapter/cross-check, not a substitute for reviewed evidence or the
  engine's later command-registry MCP surface

Expected telemetry behavior:

- reuse the Prometheus-compatible lookup and discovery baseline for onboarding and sanity checks
- batch discovery support is inherited through the Prometheus-compatible discovery interface
- direct and aggregate live status consume fresh reviewed downstream evidence;
  release targets use packaged evidence references and portfolios use explicit
  evidence paths plus runtime mappings
- opt-in `bundle verify` packages current evidence and records the full neutral
  live-status report when every downstream binding is readable; it never runs
  Sloth or reloads Prometheus

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
