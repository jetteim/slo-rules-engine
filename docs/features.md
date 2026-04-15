# Feature Inventory

This file tracks the long-running migration scope.

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

## Primary Capability: Generate SLIs And SLOs From Telemetry

The most important onboarding path is telemetry lookup first, then generated candidate review. The engine should let maintainers start with existing measured telemetry and produce a reviewable service definition draft before any provider artifact generation.

Explicit features:

- **Telemetry inventory ingestion:** accept measured telemetry inventory JSON as the starting input.
- **Signal eligibility review:** reject unsupported, non-user-visible, or metric-less signals with machine-readable findings.
- **SLI/SLO candidate inference:** map eligible signals to SLI identifiers, SLO identifiers, objectives, success conditions, and calculation-basis recommendations.
- **Draft definition generation:** emit a public-safe Ruby DSL draft with candidate SLIs, metric bindings, instances, and proposed SLOs.
- **Generated draft validation:** ensure emitted drafts can be loaded by the DSL and validated before provider generation.
- **Review handoff:** preserve findings and conservative review wording so generated SLOs remain proposals until a maintainer accepts them.
- **Provider handoff:** keep backend-specific generation downstream of accepted definitions; providers translate accepted intent and do not invent SLO policy.

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
