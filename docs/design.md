# Design

## Architecture

The engine has three layers:

1. DSL compatibility layer for service level definitions.
2. Neutral model and validation layer.
3. Provider layer for generated SLO backend artifacts and telemetry reality checks.
4. Delivery integration layer for notification route catalogs.

The core model is provider-neutral. Provider modules own backend syntax and capability gaps.

## Data Flow

```text
Ruby DSL file
  -> parser
  -> ServiceLevelDefinition
  -> core validation
  -> provider validation
  -> provider artifact manifests
  -> delivery integration route catalogs
```

## SLI/SLO Generation From Telemetry

Onboarding can start from measured telemetry:

1. Provider lists or receives available telemetry.
2. Engine groups signals by latency, traffic, errors, saturation, freshness, availability, and user journeys.
3. Engine proposes candidate SLIs and SLO success conditions.
4. Reality check estimates objective ratios and calculation basis from historical telemetry.
5. Human review accepts or rejects candidates.

Measured telemetry is evidence, not authority. A metric becomes an SLI only when it can be explained as user-visible service quality.

## Contextual Alerts

Alerts must include:

- service
- owner
- environment
- SLI
- SLO
- current burn rate or status
- impact statement
- dashboard link
- playbook link when known
- notification route key

Backends may format this differently, but the intent is the same.

## Public Safety

The repository must remain free of organization-specific references. A forbidden-term scan is part of the test suite.
