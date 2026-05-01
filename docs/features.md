# Feature Inventory

This file tracks the long-running migration scope.

See [Evolution Plan](evolution-plan.md) for value streams, capability mapping, contribution streams, and delivery order.

## Keep

- Ruby service level definition DSL.
- SLI, SLI instance, SLO, objective, success condition, and calculation-basis concepts.
- Validation of naming, required fields, uniqueness, SLO objective ranges, and metric binding completeness.
- Validation that SLO alert route keys and provider-specific route sources exist.
- Reality checks against historical telemetry and measured metric inventories.
- SLI/SLO candidate generation from measured telemetry with findings for rejected or incomplete signals.
- Generation of SLO rules, burn-rate alerts, telemetry-gap notifications, dashboards, and notification routing.
- Compatibility reports for legacy DSL and implementation-coupled definitions.
- Golden-style tests for generated artifacts.

## Onboarding Capability: Generate SLIs And SLOs From Telemetry

For services with existing telemetry, the most important onboarding path is telemetry lookup first, then generated candidate review. The engine should let maintainers start with measured telemetry and produce a reviewable service definition draft before any provider artifact generation.

Explicit features:

- **Telemetry inventory ingestion:** accept measured telemetry inventory JSON as the starting input.
- **Telemetry discovery baseline:** discover active metrics by service or selector scope before candidate review.
- **Signal eligibility review:** reject unsupported, non-user-visible, or metric-less signals with machine-readable findings.
- **SLI/SLO candidate inference:** map eligible signals to SLI identifiers, SLO identifiers, objectives, success conditions, and calculation-basis recommendations.
- **Draft definition generation:** emit a public-safe Ruby DSL draft with candidate SLIs, metric bindings, instances, and proposed SLOs.
- **Generated draft validation:** ensure emitted drafts can be loaded by the DSL and validated before provider generation.
- **Review handoff:** preserve findings and conservative review wording so generated SLOs remain proposals until a maintainer accepts them.
- **Provider handoff:** keep backend-specific generation downstream of accepted definitions; providers translate accepted intent and do not invent SLO policy.

## Reliability Model Report

`rules-ctl model-report` summarizes the neutral reliability model for service definitions. It is intended for review before provider generation and uses synthetic examples in this repository.

## Backend Telemetry Lookup And Sanity Checks

Telemetry-derived SLO generation should work from either a checked-in telemetry inventory fixture or backend lookup output. Lookup adapters normalize provider evidence before it reaches candidate generation, so SLI/SLO review does not depend on backend-specific query syntax.

Explicit features:

- **Provider telemetry lookup:** query Datadog or Prometheus-compatible backends through injectable clients and emit normalized telemetry inventory.
- **Service-scoped discovery:** inventory active metrics by service or selector scope through `discover-telemetry` and reuse the same normalized evidence shape as explicit lookup.
- **Online sanity checks:** report missing metrics, missing time series, missing histogram buckets, and calculation-basis sensitivity from file telemetry, saved lookup results, or explicit online lookup.
- **Calculation-basis evidence:** use observed request volume and estimated failed observations before alerting to recommend observations-based or time-slice-based SLOs.
- **Candidate reuse:** feed lookup or discovery output into the same `candidates` and `draft-definition` flow as file-based telemetry inventory.
- **No hidden policy:** lookup output is evidence for review, not automatic SLO acceptance.

## Provider State Management

Provider generation is read-only. Backend state changes belong to explicit apply workflows.

Explicit features:

- **State pipeline contract:** model backend management as sources, transforms, sinks, and findings.
- **Automation modes:** providers declare `live_api`, `manifest_bundle`, or `external_generator`.
- **Reviewed manifest input:** apply workflows accept a reviewed provider manifest directly instead of forcing regeneration in the same command.
- **Reviewed manifest diff:** diff workflows compare desired reviewed manifests to observed provider state and emit `create`, `update`, or `noop` operations with changed paths.
- **Apply planning:** dry-run apply emits planned create, update, write, or handoff operations.
- **Explicit live mutation:** live backend changes require a separate command, confirmation, and credentials when the provider needs them.
- **Datadog live API support:** Datadog can apply SLOs, monitors, telemetry-gap monitors, and dashboards through API calls.
- **Payload provenance:** Datadog apply operations preserve the source artifact path in each payload; provider-schema conformance and live account validation remain required before production use.
- **Manifest-backed providers:** Prometheus-compatible bundles and Sloth specs use the same apply command but initially manage files and handoff plans rather than mutating live backends.
- **Future provider contract:** new providers must document generation, reality-check, telemetry lookup, and apply behavior before being considered production-grade.

## Sloth Provider Generation

`rules-ctl generate --provider sloth` emits Sloth `prometheus/v1` SLO specs from reviewed service definitions. The provider uses Prometheus-compatible query bindings and keeps OpenSLO as a future interchange/export path, not as a backend provider.

## Change

- Provider abstraction means complete observability backend bundle.
- Backend-specific details move out of core DSL and into providers.
- Alert delivery goes through generated contextual routes.
- Public examples use generic services and public-safe domains.
- Configuration replaces hard-coded platform constants.

## Remove

- Organization-specific service names.
- Internal domains and CI references.
- Internal project metadata APIs.
- Platform-specific deployment writers.
- Secret formats tied to one organization.

## Preserve As Migration Knowledge

- Error-budget burn-rate thresholds.
- Observation-based and time-slice-based SLO calculation.
- Missing metric and missing telemetry detection.
- Provider-specific capability validation.
- Dashboard links from alerts.
- Route availability checks before alert delivery.
