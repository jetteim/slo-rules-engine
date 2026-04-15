# Sloth Provider Architecture Brief

**Parent:** Provider-independent SLO definition to backend artifact bundle.

**Decision:** Add `sloth` as the next provider and reclassify OpenSLO as an interchange/export candidate rather than a backend provider candidate.

**Outcome:** Prometheus-oriented users can generate Sloth-compatible SLO specs from reviewed neutral reliability intent without needing live backend access.

**Scope:** Include a deterministic Sloth provider that emits `prometheus/v1` Sloth specs from existing service definitions and Prometheus metric bindings. Exclude Sloth CLI execution, Kubernetes CRD generation, live apply flows, and OpenSLO export.

**Architecture impact:** Component-level change inside `slo-rules-engine`: provider registry gains `Providers::Sloth`; provider generation maps neutral SLO intent to Sloth service specs; docs move `sloth` from future candidate to initial provider and move `openslo` to export/interchange candidates.

**Implementation handoff:** Add provider tests first, implement the provider, register it, update checkout provider bindings, update CLI/docs, and run full verification.

**Evidence:** Sloth official docs describe it as a Prometheus SLO generator that delegates to Prometheus and uses a default `prometheus/v1` spec that generates standard Prometheus recording and alerting rules.

**Open questions:** None blocking this first slice. The first slice emits a Sloth spec artifact only; future work can add Kubernetes CRD output or OpenSLO export if explicitly planned.

## Candidate Review

| Candidate | Decision | Reason |
| --- | --- | --- |
| `sloth` | Choose now | High leverage for Prometheus users, deterministic local generation, matches existing Prometheus binding work, small implementation surface. |
| `openslo` | Reclassify | It is a vendor-neutral SLO specification, not a backend bundle; keep it as a future export/interchange target. |
| `grafana_cloud` | Defer | Valuable but overlaps `prometheus_stack` and requires SaaS-specific API/resource modeling. |
| `newrelic`, `honeycomb`, `nobl9`, `chronosphere` | Defer | Potentially useful but larger provider-specific semantics and validation surface. |
| `terraform` | Defer | Broadly useful but too generic for the next provider slice; better after provider schemas stabilize. |
| `perses` | Defer | Dashboard-focused; not enough SLO evaluation surface by itself. |

## C4 Component View

**Question:** Where does Sloth fit without letting provider code decide reliability policy?

**Audience:** maintainers and provider contributors.

**C4 level:** component.

## Elements

- Ruby DSL: captures service reliability definitions and metric bindings.
- Neutral model: owns SLI/SLO intent, objective, calculation basis, measurement details, miss-policy, and observability handoff.
- Core validator: checks provider-independent shape and reliability review gates.
- Sloth provider: translates reviewed neutral intent plus Prometheus-compatible bindings into Sloth `prometheus/v1` specs.
- Provider registry: exposes `sloth` through existing CLI generation.

## Relationships

- Ruby DSL -> Neutral model: builds provider-independent service definitions.
- Neutral model -> Sloth provider: supplies reviewed reliability intent and metric bindings.
- Sloth provider -> Generated manifest: emits Sloth spec artifacts as deterministic data.
- CLI -> Provider registry: routes `generate --provider sloth` through the existing provider interface.

## Decisions

- Sloth uses Prometheus-compatible query bindings and validates `prometheus` or `openmetrics` data sources.
- The provider emits Sloth specs as manifest artifacts; it does not run `sloth generate`.
- Objective ratios remain model decisions and are converted to Sloth percentage values at the provider boundary.
- OpenSLO is not listed as a backend provider candidate in README.

## Risks / NFRs

- Determinism: identical input must produce identical Sloth spec artifacts.
- Public safety: docs and fixtures stay synthetic and forbidden-term tests remain clean.
- Scope control: no network, credentials, live backend mutation, or Sloth CLI dependency.
- Policy boundary: provider code must not choose objectives, calculation basis, ownership, or page policy.
