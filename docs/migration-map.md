# Migration Map

The old implementation is used only as behavior evidence. No internal names, URLs, service definitions, secrets, or platform deployment files are copied into this project.

## Current Behavior To Rebuild

- Parse Ruby service definitions.
- Validate service, SLI, SLI instance, and SLO structure.
- Validate objective ranges and calculation basis.
- Validate provider-specific metric bindings.
- Generate short-window and long-window SLO rules for Prometheus-compatible backends.
- Generate SLOs, monitors, and dashboards for Datadog.
- Generate contextual alert routing.
- Generate service dashboards.
- Run reality checks against measured telemetry.
- Produce machine-readable validation output.

## Current Coupling To Remove

- Hard-coded internal URLs.
- Internal organization names and business units.
- Platform-specific cluster naming.
- Platform-specific deployment writers.
- Internal notification bot assumptions.
- Internal source repository links.
- Internal project metadata lookup.

## Target Shape

The DSL produces neutral reliability intent.

Providers translate that intent into backend artifacts:

- `datadog`
- `prometheus_stack`
- `notification_router`

Additional providers can be added without changing the DSL model.
