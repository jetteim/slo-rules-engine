# Feature Inventory

This file tracks the long-running migration scope.

## Keep

- Ruby service level definition DSL.
- SLI, SLI instance, SLO, objective, success condition, and calculation-basis concepts.
- Validation of naming, required fields, uniqueness, SLO objective ranges, and metric binding completeness.
- Reality checks against historical telemetry.
- SLI/SLO candidate generation from measured telemetry.
- Generation of SLO rules, alerts, dashboards, and notification routing.
- Golden-style tests for generated artifacts.

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
- Missing metric detection.
- Provider-specific capability validation.
- Dashboard links from alerts.
- Route availability checks before alert delivery.
