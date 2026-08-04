# Live SLO Status Contract

This contract separates reviewed reliability intent from provider-specific live
evidence. It reads one reviewed Prometheus Stack manifest directly or aggregates
readable targets from one current release bundle or explicit portfolio. It does
not mutate provider state.

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

## Aggregate Report Shape

Bundle and portfolio modes emit
`slo-rules-engine/live-slo-status-aggregate/v1`
`LiveSLOStatusAggregateReport`.

Top-level fields:

- scope: `release_bundle` or `portfolio`
- source path, source fingerprint, and bundle identity/lifecycle or exact
  manifest path/fingerprint entries
- one check timestamp and freshness limit
- deterministic target, coverage, SLO-state, and evidence-completeness rollups
- target envelopes sorted by `service/provider`
- optional saved report path

A readable Prometheus Stack target has `outcome: reported` and contains its
complete `slo-rules-engine/live-slo-status/v1` report unchanged. A Datadog or
Sloth target has `outcome: unsupported` and a stable
`unsupported_live_status_provider` finding; it is not silently omitted.
`coverage_complete` is false when any target is unsupported.
`evidence_complete` is false when coverage is incomplete, no SLO is available,
or any SLO is `missing_telemetry` or `unverifiable`.

A provider query failure remains inside that target's report as
`unverifiable`. Other target reports remain available and the command exits
zero because the aggregate was produced. Invalid or stale source input and
runtime preflight failures exit nonzero before any backend read.

## Aggregate Inputs And Runtime

Release-bundle mode accepts one valid `review_ready`, `apply_ready`, `applied`,
or `verified` `slo-rules-engine/release-bundle/v1`. Before any backend read it
validates schema, content-addressed bundle identity, packaged artifact
fingerprints, current file-backed source fingerprints, embedded manifests,
review provenance, and target identity. The aggregate source links the bundle
path, ID, effective lifecycle, and loaded-content fingerprint.

Portfolio mode accepts a credential-free file:

```json
{
  "schema_version": "slo-rules-engine/live-status-portfolio/v1",
  "kind": "LiveStatusPortfolio",
  "targets": [
    {
      "uid": "checkout-api/prometheus_stack",
      "manifest": "generated/checkout-api/prometheus_stack/manifest.json"
    },
    {
      "uid": "search-api/prometheus_stack",
      "manifest": "generated/search-api/prometheus_stack/manifest.json"
    }
  ]
}
```

Relative manifest paths resolve from the portfolio file. The resolver validates
every manifest schema, review provenance, unique UID, and exact
`service/provider` identity before reading a backend. The aggregate source
records the loaded portfolio and manifest fingerprints.

Runtime endpoints are supplied separately with one
`--target-base-url=service/provider=URL` per readable target. All mappings are
validated before a client is created. Missing, unknown, duplicate,
credential-bearing, query-bearing, fragment-bearing, or non-HTTP(S) URLs fail
the command. Mappings for unsupported targets are rejected. Runtime URLs are
used only to construct clients and are never persisted in bundles, portfolios,
or reports.

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
report exits zero even when an SLO is unhealthy. Invalid input and missing
review provenance exit nonzero. Direct single-manifest status rejects an
unsupported provider; aggregate status reports unsupported targets explicitly
and rejects an input with no readable targets.

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

- no Datadog reader until safe live evidence work resumes
- no Sloth reader yet; the reviewed downstream generated-rule identity schema
  now exists, but status does not consume it until the next provider-reader
  slice adds freshness preflight and explicit runtime mapping
- no automatic endpoint discovery or one-URL assumption across aggregate
  targets
- freshness is evaluated from the success-ratio record; every provider sample
  timestamp is still retained as evidence
