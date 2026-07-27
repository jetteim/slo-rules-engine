# Live SLO Status Contract

This contract separates reviewed reliability intent from provider-specific live
evidence. The first implementation reads one reviewed Prometheus Stack
manifest. It does not mutate provider state.

## Neutral Intent

Every SLO has:

- a reviewed objective ratio
- an evaluation window, defaulting to `30d`
- an observation-based or time-slice calculation basis
- a success condition
- owner, dashboard, playbook, route, and miss-policy context

Prometheus Stack generation records the evaluation window as a label and emits
one record each for success ratio, error ratio, objective ratio, allowed error
budget, and remaining error budget. Burn-rate records evaluate their own policy
windows.

## Report Shape

The schema is `slo-rules-engine/live-slo-status/v1` and the kind is
`LiveSLOStatusReport`.

Top-level fields:

- provider, service, review provenance, check timestamp, and freshness limit
- summary counts for all five states
- one normalized status per reviewed SLO
- report-level findings
- optional saved report path

Each SLO status contains:

- reviewed service, SLI, instance, and SLO identity
- reviewed objective, provider-observed objective, evaluation window,
  calculation basis, measured success ratio, and attainment
- reviewed and provider-observed budget allowance plus remaining and consumed
  ratios
- burn-rate values, thresholds, and breach flags by window
- observation value, source timestamp, age, freshness limit, and freshness
  decision
- owner, dashboard, and playbook
- generated provider resource names
- provider query expressions, values, sample timestamps, and read outcomes
- machine-readable findings

Provider query syntax is evidence only. It does not enter the neutral SLO
definition or classification contract.

## Classification

Classification is deterministic and uses this precedence:

1. `unverifiable`: the manifest lacks a required rule, a result is ambiguous or
   invalid, a provider read fails, or the provider objective/budget differs from
   reviewed intent.
2. `missing_telemetry`: a required series is absent or the success-ratio source
   timestamp exceeds the freshness limit.
3. `exhausted`: normalized remaining error budget is zero.
4. `at_risk`: a burn threshold is breached or the measured objective is not
   attained while the budget record is not exhausted.
5. `healthy`: reviewed intent matches provider evidence, telemetry is fresh,
   the objective is attained, budget remains, and no burn threshold is
   breached.

The state is operational data, not command validity. A successfully generated
report exits zero even when an SLO is unhealthy. Invalid input, missing review
provenance, and unsupported providers exit nonzero.

## Prometheus Read Boundary

For each SLO, the reader performs GET-only `/api/v1/query` calls for:

- SLI observations
- SLO success ratio
- reviewed objective record
- allowed error-budget record
- remaining error-budget record
- every generated burn-rate record
- `timestamp(success_ratio)` for freshness

No query is inferred from the neutral DSL. Every expression is taken from the
reviewed provider manifest. The report retains the expression and sanitized
error class but never a raw backend error message or credential.

## Current Limits

- exactly one reviewed `prometheus_stack` manifest per command
- no release-bundle or portfolio aggregation yet
- no Datadog reader until safe live evidence work resumes
- no Sloth reader until downstream generated recording-rule identity is
  captured
- freshness is evaluated from the success-ratio record; every provider sample
  timestamp is still retained as evidence
