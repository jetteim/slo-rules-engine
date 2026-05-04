# Evolution Plan

This document describes how the engine should evolve from a public-safe DSL skeleton into a provider-independent SLO workflow with contribution paths for new backends.

## Product Intent

The engine keeps service reliability intent independent from observability backends. A service definition should describe what reliability means for a service; providers then translate that intent into backend artifacts.

Existing telemetry and prior implementation behavior are evidence for better modeling, not authority. They can suggest candidates, gaps, and compatibility work, but accepted SLO policy remains in the neutral model.

## Value Streams

### 1. Provider-Independent SLO Definition To Backend Artifact Bundle

**Customer / beneficiary:** service maintainers and platform/SRE teams.

**Trigger:** a maintainer creates or updates a service-level definition.

**Outcome:** validated provider-independent reliability intent is translated into backend-specific SLO rules, burn-rate alerts, missing-telemetry checks, dashboards, route references, and manifests.

**Flow:**

1. Author or generate a service reliability definition in the neutral Ruby DSL.
2. Parse DSL into provider-independent model objects.
3. Validate service, SLI, instance, SLO, objective, routing, calculation basis, and telemetry binding shape.
4. Review reliability intent, including measurement assumptions, alert context, miss-policy, and observability gaps.
5. Select a provider bundle.
6. Validate provider capability coverage and unsupported fields.
7. Generate backend artifacts and manifests.
8. Generate delivery integration route catalogs where required.
9. Run reality checks against measured telemetry before trusting generated output.

**Measures:**

- Validated definitions generated per service.
- Provider generation failures caught before artifact output.
- Generated artifacts trace back to neutral service intent.

### 2. Existing Telemetry To Draft SLO Definition

**Customer / beneficiary:** maintainers onboarding services with telemetry but no reviewed SLO definition.

**Trigger:** measured telemetry inventory or backend discovery output exists.

**Outcome:** a loadable Ruby DSL draft with candidate SLIs/SLOs and findings for rejected signals.

**Flow:**

1. Discover or ingest telemetry inventory.
2. Classify signals by reliability meaning.
3. Reject unsupported, non-user-visible, or incomplete signals with findings.
4. Infer candidate SLIs, SLOs, objectives, success conditions, and calculation basis.
5. Emit a public-safe Ruby DSL draft.
6. Validate the generated draft.
7. Feed accepted draft definitions into the provider-independent SLO stream.

**Measures:**

- Time from telemetry discovery or inventory to validated draft.
- Eligible signal conversion rate.
- Findings per telemetry inventory.

### 3. Reviewed SLO Intent To Operational Alert Response

**Customer / beneficiary:** responders receiving SLO alerts or notifications.

**Trigger:** an SLO burns error budget or required telemetry disappears.

**Outcome:** responder receives contextual alert or notification with owner, impact, SLI/SLO identity, route key, dashboard, and playbook context.

**Flow:**

1. Generate burn-rate and missing-telemetry artifacts from accepted SLO intent.
2. Attach contextual labels and annotations.
3. Generate decision dashboard references and variables.
4. Generate route catalog entries.
5. Verify route availability where integration output supports it.
6. Deliver page-worthy alerts and non-page notifications through configured channels.

**Measures:**

- Alerts with complete action context.
- Telemetry-gap signals classified as notifications unless impact requires action.
- Route availability failures found before incident response depends on them.

### 4. Service Telemetry Discovery To Reviewed Onboarding Queue

**Customer / beneficiary:** platform and SRE teams onboarding multiple services that already emit telemetry.

**Trigger:** many services expose telemetry, but there is no reviewed SLO definition backlog or prioritization.

**Outcome:** prioritized onboarding queue with discovery evidence, candidate packs, and reviewable draft definitions.

**Flow:**

1. Discover telemetry across service or selector scopes.
2. Group signals into service-level evidence packets.
3. Score signal eligibility, coverage, and review readiness.
4. Emit candidate packs and reviewable draft definitions.
5. Preserve findings and candidate reasoning as review evidence.
6. Prioritize services for maintainer review.
7. Feed accepted drafts into the provider-independent SLO stream.

**Measures:**

- Services discovered per run.
- Review-ready service ratio.
- Time from discovery to accepted draft.

### 5. Provider Contribution To Supported Backend Bundle

**Customer / beneficiary:** contributors adding or extending backend support.

**Trigger:** a contributor wants to add a provider or improve provider coverage.

**Outcome:** provider deterministically translates neutral reliability intent into backend artifacts and reports unsupported fields explicitly.

**Flow:**

1. Read the provider contract and contribution rules.
2. Declare provider capabilities.
3. Map neutral model fields to backend artifacts.
4. Emit deterministic manifests.
5. Report unsupported fields as validation output.
6. Add synthetic fixtures and provider tests.
7. Verify public-safety and full test checks.

**Measures:**

- Provider capabilities declared and tested.
- Unsupported intent produces explicit validation output.
- Provider output remains deterministic for identical input.

### 6. Reviewed Artifact Manifest To Managed Backend State

**Customer / beneficiary:** operators reconciling generated artifacts with live backend state.

**Trigger:** reviewed artifact manifests are ready to compare or apply.

**Outcome:** backend state can be planned, diffed, imported, applied, pruned, or cost-checked through explicit safe commands.

**Flow:**

1. Generate reviewed manifests from accepted neutral intent.
2. Compare generated output with current backend state.
3. Report drift and destructive changes before any mutation.
4. Produce a dry-run apply plan.
5. Apply or prune only through explicit commands.
6. Record generated artifact provenance.

**Measures:**

- Drift detected before apply.
- Irreversible changes require explicit confirmation.
- Backend state changes trace to generated manifests.
- Providers declare whether state is managed through live APIs, manifest bundles, or external-generator handoffs.

### 7. Existing Backend Telemetry To SLO Reality Check

**Customer / beneficiary:** maintainers verifying that definitions can be evaluated by a backend.

**Trigger:** a service definition exists and measured telemetry inventory, saved lookup output, or explicit backend lookup is available.

**Outcome:** report identifies missing provider bindings, missing backend metrics, or telemetry gaps before provider artifacts are trusted.

**Flow:**

1. Load service definition.
2. Load measured telemetry inventory or normalized lookup output.
3. Inspect provider-specific query bindings.
4. Compare required metrics with measured telemetry or explicit backend lookup.
5. Report missing bindings and missing metrics.
6. Feed findings back into definition or instrumentation work.

**Measures:**

- Missing provider bindings found before generation.
- Missing backend metrics found before alert rollout.
- Reality-check reports remain machine-readable.

## Capability Map

| Capability | Value Stream | Feature Candidates |
| --- | --- | --- |
| Provider-independent DSL authoring | 1 | Ruby DSL, service metadata, SLI/SLO blocks, metric bindings, route keys |
| Neutral reliability intent model | 1, 3 | service model, SLI model, SLO model, measurement details, miss-policy, observability handoff |
| Core validation and review gates | 1, 3 | required fields, objective ranges, calculation basis, route references, miss-policy validation |
| Provider artifact generation | 1 | Datadog manifests, Prometheus-compatible rules, dashboards, output directory layout |
| Telemetry-derived draft generation | 2 | telemetry discovery, inventory ingestion, lookup-envelope reuse, findings, candidate inference, `draft-definition` |
| Operational alert context | 3 | burn-rate alerts, telemetry-gap notifications, contextual annotations, dashboard variables |
| Delivery integration routing | 3 | route catalogs, route availability checks, notification router integration |
| Portfolio telemetry onboarding | 4 | batch discovery, onboarding queue, candidate scoring, evidence packets |
| Provider contribution safety | 5 | provider contract, provider guide, deterministic tests, unsupported-field warnings |
| Backend state management | 6 | automation modes, artifact schemas, dry-run apply plans, diff harness, apply/prune commands, import existing resources |
| Reality checking | 7 | provider binding checks, missing metric checks, backend telemetry lookup and discovery adapters |

## Delivery Order

1. Keep the provider-independent DSL and provider generation path stable.
2. Strengthen provider-state management until Datadog is a credible `live_api` baseline.
3. Make telemetry-derived draft generation and portfolio discovery a first-class onboarding path.
4. Enrich the neutral model with reliability review fields.
5. Strengthen validation and model reporting.
6. Add provider contribution guide and guardrails.
7. Add low-volume and reality-check examples with synthetic telemetry.
8. Keep provider apply behavior explicit for each provider: Datadog as live API, Prometheus-compatible bundles as manifest bundles, and Sloth as external-generator handoff.

## Guardrails

- The neutral DSL owns reliability intent; providers own backend translation.
- Existing telemetry is evidence for candidates, not automatic SLO policy.
- Legacy or private rules are evidence only and must stay outside this repository.
- Generated artifacts must be reproducible from accepted model input.
- Missing telemetry is a reliability signal; it must not be silently ignored.
- Provider contributions must use synthetic fixtures and explicit unsupported-field handling.
- Public-safety checks must remain part of the normal test path.
- Live backend mutation must require explicit confirmation and provider credentials.
