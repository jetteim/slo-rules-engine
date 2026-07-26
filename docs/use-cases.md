# Engineering Use Cases

This guide starts with the engineering job to be done, then names the commands, generated artifacts, provider differences, and mutation boundary.

Usage documentation is part of the feature contract. When command scope, provider behavior, generated artifacts, or safety boundaries change, this guide and the README must be updated in the same checkpoint.

## Output Map

### Shared workflow outputs

| Workflow stage | Output |
| --- | --- |
| Telemetry lookup | One normalized JSON envelope with `provider`, `signals`, and `findings` |
| Batch discovery | One normalized evidence file per scope plus aggregate `index.json` |
| Candidate review | Candidate SLI/SLO proposals with confidence, explanations, caveats, and rejected-signal findings |
| Onboarding handoff | One saved packet per scope with discovery evidence, candidate reasoning, and explicit accept/reject decisions |
| Draft generation | Reviewable Ruby DSL definition carrying onboarding provenance; provider bindings still require maintainer review |
| Provider generation | Reviewed provider manifest plus a provider-level manifest-review report |
| Artifact indexing | Per-scope links across discovery, handoff, reviewed definition, provider manifests, and review reports |
| Release bundling | Content-addressed `review_ready` JSON containing the reviewed evidence and target artifacts |
| Bundle planning | New content-addressed `apply_ready` JSON containing provider plans, transition lineage, and provider summaries |

### Provider generation and state outputs

| Engineering output | `datadog` | `prometheus_stack` | `sloth` |
| --- | --- | --- | --- |
| Telemetry evidence | Active-metric or explicit query evidence normalized from Datadog APIs | Metric-name, series, or explicit PromQL evidence normalized from a Prometheus-compatible API | Same Prometheus-compatible adapter, with evidence labeled for the Sloth provider |
| Reviewed manifest | SLO intent, burn-rate monitor intent, missing-telemetry monitor intent, dashboard intent, and route context | Recording rules, burn-rate rules, telemetry-gap alerts, burn-rate alerts, Grafana dashboards, Alertmanager routes, and rendered native resources | Sloth `prometheus/v1` SLO specs with event queries, page/ticket alert labels, and annotations |
| Saved review report | `manifest-review/datadog.json` | `manifest-review/prometheus_stack.json` | `manifest-review/sloth.json` |
| Dry-run plan | Versioned desired/observed state plus API payload operations: `create`, `update`, `recreate`, or `noop`; includes managed identity and Datadog risk evidence | Versioned desired/observed state plus managed-file operations: `write` or `noop` for manifest and native resource files | Versioned desired/observed state plus managed-file `write` or `noop` operations and an external `sloth generate` handoff operation |
| Confirmed output | Datadog SLOs, monitors, telemetry-gap monitors, and dashboards | Reviewed manifest, PrometheusRule YAML, Grafana dashboard ConfigMap YAML, and Alertmanager route-intent YAML | Reviewed manifest and native Sloth YAML input |
| What remains external | Notification endpoint/credential ownership | Applying Kubernetes resources, Grafana sidecar loading, and Alertmanager receiver endpoint/credentials | Running Sloth, applying generated Prometheus rules, and configuring Alertmanager |

## Use Case 1: Find Candidate SLOs In Existing Telemetry

**Task:** a service has metrics but no reviewed SLO definition. Inventory what exists before writing policy.

For Datadog:

```bash
bin/rules-ctl discover-telemetry \
  --provider=datadog \
  --service=checkout-api \
  > ./work/checkout-datadog-evidence.json
```

For Prometheus Stack:

```bash
bin/rules-ctl discover-telemetry \
  --provider=prometheus_stack \
  --service=checkout-api \
  --base-url=http://localhost:9090 \
  > ./work/checkout-prometheus-evidence.json
```

For a Sloth delivery target, use the same Prometheus-compatible discovery path:

```bash
bin/rules-ctl discover-telemetry \
  --provider=sloth \
  --service=checkout-api \
  --base-url=http://localhost:9090 \
  > ./work/checkout-sloth-evidence.json
```

Rank one evidence file:

```bash
bin/rules-ctl candidates ./work/checkout-datadog-evidence.json
```

**Generated result:**

- normalized signals rather than raw provider responses
- proposed candidate SLI/SLO identities and calculation basis
- confidence level, evidence reasons, caveats, and explanation
- findings for unknown, non-user-visible, incomplete, or unsupported telemetry

**Safety boundary:** discovery and candidate generation do not create policy or backend resources. Objectives and thresholds remain proposals until reviewed.

## Use Case 2: Build A Portfolio Onboarding Queue

**Task:** inspect many service scopes in one provider and leave a reusable queue for service owners.

```bash
bin/rules-ctl discover-telemetry \
  --provider=datadog \
  --scope-file=./examples/telemetry/scopes.json \
  --output-dir=./work/discovery

bin/rules-ctl onboarding-summary \
  --handoff-dir=./work/handoff \
  ./work/discovery/index.json
```

Review one scope:

```bash
bin/rules-ctl review-handoff \
  --accept=request-latency \
  --reject=request-traffic \
  --note='Latency represents the reviewed user journey.' \
  ./work/handoff/checkout-prod.handoff.json

bin/rules-ctl validate-handoff \
  ./work/handoff/checkout-prod.handoff.json
```

Create the neutral draft:

```bash
bin/rules-ctl draft-from-handoff \
  --service=checkout-api \
  --owner=payments-platform \
  ./work/handoff/checkout-prod.handoff.json \
  > ./work/drafts/checkout-prod.rb
```

**Generated result:**

- per-scope normalized discovery evidence
- aggregate discovery index with runtime failures preserved
- readiness ranking: `ready`, `partial`, `insufficient`, or `failed`
- accepted and rejected candidate decisions with review notes
- a Ruby DSL draft carrying the original discovery-provider provenance

**Safety boundary:** generated drafts intentionally contain provider-binding handoff work. A maintainer must verify metric semantics, thresholds, selectors, routes, dashboards, and miss policy before provider generation.

## Use Case 3: Discover With One Provider And Deliver Through Another

**Task:** use evidence from the backend currently deployed, but generate the reviewed SLO for a different destination.

Example: discover in Datadog, generate for Prometheus Stack.

1. Discover, rank, and review Datadog evidence as shown above.
2. Generate the neutral draft from the accepted handoff.
3. Add a reviewed `prometheus_stack` binding to the accepted metric:

```ruby
provider_binding 'prometheus_stack' do
  metric 'http_server_request_duration_seconds_count'
  data_source 'prometheus'
  type 'counter'
  selector service: 'checkout-api'
end
```

4. Add the required Alertmanager notification route and validate against target telemetry:

```bash
bin/rules-ctl validate ./work/drafts/checkout-prod.rb

bin/rules-ctl reality-check \
  --provider=prometheus_stack \
  --online \
  --base-url=http://localhost:9090 \
  ./work/drafts/checkout-prod.rb
```

5. Generate the target bundle:

```bash
bin/rules-ctl generate \
  --provider=prometheus_stack \
  --output-dir=./work/generated \
  --handoff-dir=./work/handoff \
  ./work/drafts/checkout-prod.rb
```

**Generated result:**

- the handoff and definition retain `datadog` as the source of onboarding evidence
- target generation uses only the explicit reviewed `prometheus_stack` binding
- the provider manifest contains recording, alert, dashboard, and route artifacts
- `manifest-review/prometheus_stack.json` links the target manifest back to the reviewed handoff

The reverse is also supported: discover Prometheus telemetry, accept the candidate, add a reviewed Datadog metric/query binding, run a Datadog reality check, and generate Datadog resources.

A single definition may carry all three bindings:

```bash
bin/rules-ctl generate --provider=datadog --output-dir=./work/generated ./work/checkout-api.rb
bin/rules-ctl generate --provider=prometheus_stack --output-dir=./work/generated ./work/checkout-api.rb
bin/rules-ctl generate --provider=sloth --output-dir=./work/generated ./work/checkout-api.rb
```

**Cross-provider boundary:**

- portable: discovered signal kind, evidence counts, candidate reasoning, accepted SLO identity, objective, calculation basis, miss policy, owner, and review notes
- target-specific: metric names, query syntax, selectors, aggregation semantics, histogram shape, routes, dashboard paths, and resource payloads
- never automatic: the engine does not infer that one provider metric/query is semantically equivalent to another

## Use Case 4: Generate A Complete Provider Delivery Bundle

**Task:** translate one reviewed service definition into the artifacts required by the selected observability backend.

```bash
bin/rules-ctl generate \
  --provider=datadog \
  --output-dir=./work/generated \
  --handoff-dir=./work/handoff \
  ./work/checkout-api.rb
```

Change `--provider` to `prometheus_stack` or `sloth` for another target.

**Datadog generates:**

- one SLO intent per reviewed SLO
- burn-rate monitor intent
- missing-telemetry monitor intent
- decision dashboard intent
- route and response context
- saved reviewed manifest and Datadog manifest-review report

**Prometheus Stack generates:**

- one base observation recording rule per SLI instance
- success-ratio, error-ratio, objective-ratio, and error-budget-ratio rules per SLO
- burn-rate recording rules and alerts
- missing-telemetry alerts
- Grafana dashboards
- Alertmanager route intent
- rendered PrometheusRule, dashboard ConfigMap, and route-intent resources
- saved reviewed manifest and Prometheus Stack manifest-review report

**Sloth generates:**

- `prometheus/v1` SLO specifications
- error and total event queries
- page and ticket alert labels
- dashboard, playbook, miss-policy, owner, and route annotations
- saved reviewed manifest and Sloth manifest-review report

Validate a saved report against the current manifest and handoff:

```bash
bin/rules-ctl manifest-review \
  --provider=prometheus_stack \
  --manifest=./work/generated/checkout-api/prometheus_stack/manifest.json \
  --handoff-dir=./work/handoff \
  --report=./work/generated/manifest-review/prometheus_stack.json
```

## Use Case 5: Package A Reviewed Multi-Provider Release

**Task:** create one immutable artifact that records what was reviewed for several provider targets.

Build an index containing each generated provider:

```bash
bin/rules-ctl onboarding-artifact-index \
  --handoff-dir=./work/handoff \
  --draft-dir=./work/drafts \
  --manifest-dir=./work/generated \
  --provider=datadog \
  --provider=prometheus_stack \
  --provider=sloth \
  --output=./work/artifact-index.json \
  ./work/discovery/index.json
```

Create the review boundary:

```bash
bin/rules-ctl bundle create \
  --artifact-index=./work/artifact-index.json \
  --reviewer=team/payments-sre \
  --reviewed-at=2026-07-26T09:30:00Z \
  --output=./work/review-ready.json
```

Plan every target:

```bash
bin/rules-ctl bundle plan ./work/review-ready.json \
  --target-backend=checkout-api/datadog=environment \
  --target-output=checkout-api/prometheus_stack=./managed \
  --target-output=checkout-api/sloth=./managed \
  --output=./work/apply-ready.json
```

**Generated result:**

- new bundle ID; the input bundle is unchanged
- one generated plan artifact per provider target
- transition lineage back to the `review_ready` predecessor
- provider-level target, plan, operation, destructive, and risk counts
- action, resource-target, and risk-level breakdowns

**Provider reads during planning:**

- Datadog reads current managed backend state using runtime credentials
- Prometheus Stack reads the configured managed-file directory
- Sloth reads the configured managed-file directory

No provider mutation occurs.

## Use Case 6: Understand Drift Before Applying

**Task:** compare reviewed desired state with current provider state.

Datadog:

```bash
bin/rules-ctl diff \
  --provider=datadog \
  --manifest=./work/generated/checkout-api/datadog/manifest.json
```

Prometheus Stack:

```bash
bin/rules-ctl diff \
  --provider=prometheus_stack \
  --output-dir=./managed \
  --manifest=./work/generated/checkout-api/prometheus_stack/manifest.json
```

Sloth:

```bash
bin/rules-ctl diff \
  --provider=sloth \
  --output-dir=./managed \
  --manifest=./work/generated/checkout-api/sloth/manifest.json
```

**Generated result:**

- Datadog: `create`, `update`, `recreate`, or `noop` operations with changed paths, backend IDs, match identity, and risk where applicable
- Prometheus Stack: `create`, `update`, or `noop` comparisons for the manifest and each native managed file
- Sloth: `create`, `update`, or `noop` comparisons for the manifest and native Sloth input
- all providers: `slo-rules-engine/provider-state/v1` desired-state and observed-state snapshots, deterministic fingerprints, normalized changes, provider findings, and the existing impact summary under `state_contract`

`diff` never mutates provider state.

## Use Case 7: Inventory Existing Managed State

**Task:** determine what the engine can match, what is missing, and what may be orphaned before adoption.

```bash
bin/rules-ctl import \
  --provider=datadog \
  --manifest=./work/generated/checkout-api/datadog/manifest.json
```

For file-backed providers add `--output-dir=./managed`.

**Generated result:**

- Datadog: matched backend state, missing expected resources, managed orphan findings, and match-identity confidence
- Prometheus Stack: current manifest and every expected native file, with missing-file findings
- Sloth: current manifest and every expected native Sloth input, with missing-input findings
- all providers: versioned desired-state, observed-state, and normalized finding evidence under `state_contract`

Import is observational. It does not adopt, update, or delete resources.

## Use Case 8: Apply Reviewed State

**Task:** converge current provider state after the plan and review evidence have been inspected.

Datadog:

```bash
bin/rules-ctl apply \
  --provider=datadog \
  --confirm \
  --manifest=./work/generated/checkout-api/datadog/manifest.json \
  --handoff-dir=./work/handoff \
  --review-report=./work/generated/manifest-review/datadog.json
```

Prometheus Stack:

```bash
bin/rules-ctl apply \
  --provider=prometheus_stack \
  --confirm \
  --output-dir=./managed \
  --manifest=./work/generated/checkout-api/prometheus_stack/manifest.json \
  --handoff-dir=./work/handoff \
  --review-report=./work/generated/manifest-review/prometheus_stack.json
```

Sloth:

```bash
bin/rules-ctl apply \
  --provider=sloth \
  --confirm \
  --output-dir=./managed \
  --manifest=./work/generated/checkout-api/sloth/manifest.json
```

**Mutation result:**

- Datadog creates or updates API resources; risky weak-ownership updates are blocked
- Prometheus Stack writes only changed deterministic bundle files
- Sloth writes only changed manifest and native input files; running Sloth remains external

Current `apply` replans immediately before mutation. It does not yet promise execution of a separately approved exact plan; that is a later explicit workflow phase.

## Use Case 9: Remove Managed Orphans

**Task:** inspect and explicitly remove provider state that is managed for the service but absent from reviewed desired state.

Start with dry-run:

```bash
bin/rules-ctl prune \
  --provider=datadog \
  --dry-run \
  --manifest=./work/generated/checkout-api/datadog/manifest.json
```

Confirmed prune uses `--confirm` and should include current handoff/report evidence. File-backed providers also require `--output-dir`.

**Generated or mutation result:**

- Datadog dry-run identifies managed orphan deletes with ownership confidence and risk; confirmed prune blocks weak service-scope ownership
- Prometheus Stack dry-run identifies managed bundle files; confirmed prune deletes existing files in that reviewed bundle
- Sloth dry-run identifies its manifest and input files; confirmed prune deletes those managed files

## Use Case 10: Verify Telemetry Before Production Adoption

**Task:** prove that the selected provider binding resolves to usable evidence.

Datadog:

```bash
bin/rules-ctl reality-check \
  --provider=datadog \
  --online \
  ./work/checkout-api.rb
```

Prometheus Stack or Sloth:

```bash
bin/rules-ctl reality-check \
  --provider=prometheus_stack \
  --online \
  --base-url=http://localhost:9090 \
  ./work/checkout-api.rb
```

**Generated result:**

- provider and service identity
- validity rollup
- per-SLI reports
- findings for missing metrics, absent series, incomplete histogram evidence, or incompatible binding semantics

The command reports evidence gaps. It does not modify definitions or backend state.

## Use Case 11: Generate Contextual Alert Routes

**Task:** hand provider alert context to a delivery system without giving the rules engine delivery credentials.

```bash
bin/rules-ctl generate-routes \
  --integration=notification_router \
  ./work/checkout-api.rb
```

**Generated result:**

- Datadog route entries for Datadog-sourced notification routes
- Alertmanager route entries for Prometheus Stack and Sloth routes
- route availability-check intent

The notification router owns Teams, Slack, Telegram, webhook, console, or other channel configuration. The rules engine generates route intent and keys only.

## Maintenance Rule

Update or rewrite usage when any of these changes:

- a command is added, removed, renamed, or gains a new safety gate
- a provider starts or stops generating an artifact
- a provider automation mode or state action changes
- a workflow begins contacting a backend or mutating state
- bundle lifecycle, identity, runtime configuration, or output changes
- cross-provider evidence portability or binding requirements change

Do not append isolated command examples to an outdated catalog. Keep the guide organized around the engineering task and state the generated result for every supported provider.
