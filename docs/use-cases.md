# Engineering Use Cases

This guide describes the engineering work the tool is intended to solve, the command boundary, and the exact output to expect. Reliability intent stays in the neutral Ruby definition. Telemetry evidence informs that intent, and provider adapters generate backend-specific artifacts from reviewed bindings.

Usage documentation is part of the feature contract. When command scope, provider behavior, generated artifacts, or safety boundaries change, this guide and the README must change in the same checkpoint.

## Intent And Output Check

| Use case | Reliability intent carried forward | Primary output | Mutation boundary |
| --- | --- | --- | --- |
| Find candidates | User-visible signal evidence, not an objective decision | Normalized telemetry and ranked proposals | Read-only backend discovery |
| Build onboarding queue | Accepted/rejected evidence with reviewer notes | Saved handoff packets and reviewable Ruby draft | Handoff packet is updated; no provider mutation |
| Cross-provider delivery | One reviewed SLO with explicit binding per target | Target-provider manifest linked to source-provider evidence | No metric or query translation is inferred |
| Generate provider bundle | SLI, objective, response context, dashboard, route, and miss policy | Reviewed provider manifest and manifest-review report | Generation is local and read-only |
| Package release | Reviewed evidence and target identity | Immutable review and apply-ready bundle JSON | Planning reads state but does not mutate it |
| Approve and execute exact plan | One reviewed target, locked evidence, and exact operation list | Content-addressed approved plan, durable journal, and provider result | Explicit approval, `--confirm`, immediate state recheck, and same-scope lock |
| Apply and verify file-backed release | Complete approved-plan coverage plus fresh engine-owned convergence for one release | Immutable applied and verified successors with per-target execution and verification evidence | Exact execution mutates approved files; later verification is read-only |
| Inspect drift | Reviewed desired state compared with observed state | Provider plan with deterministic state fingerprints | Read-only provider or managed-file access |
| Inventory state | Ownership and adoption evidence | Observed state and findings | Read-only provider or managed-file access |
| Create operation journal | Exact provider plan identity and operation safety evidence | Immutable initial journal plus status assessment | Standalone journal creation does not execute |
| Apply reviewed state | Reviewed provider artifacts and mutation gates | Durable journal plus provider result and post-operation verification | Explicit `--confirm` and `--journal-dir` |
| Remove managed state | Reviewed scope and ownership evidence | Durable journal plus confirmed delete result and absence verification | Explicit `--confirm` and `--journal-dir` |
| Verify telemetry | Provider binding backed by current evidence | Reality-check report | Read-only backend lookup |
| Review Sloth downstream rules | Reviewed Sloth intent plus externally generated rule identity | Content-addressed downstream evidence plus freshness status | Local source reads only; capture writes one explicit evidence file |
| Inspect live SLO status | Reviewed SLO identity, evaluation window, objective, budget, burn policy, response context, downstream Sloth evidence, and release/portfolio target coverage | Versioned per-manifest or aggregate live-status report with per-SLO state and freshness | Prometheus-compatible instant-query reads only; Sloth requires fresh exact-manifest evidence |
| Generate routes | Alert decision context without delivery secrets | Route catalog JSON | Delivery remains external |
| Validate Datadog contract | Explicit sandbox credential and dashboard API evidence | Public-safe sandbox smoke JSON | Read-only by default; one temporary dashboard only with explicit confirmation |

## Output Map

### Shared Workflow Outputs

| Workflow stage | Output |
| --- | --- |
| Telemetry lookup | One normalized JSON envelope with `provider`, `signals`, and `findings` |
| Batch discovery | One normalized evidence file per scope plus aggregate `index.json` |
| Candidate review | Candidate SLI/SLO proposals with confidence, explanations, caveats, and rejected-signal findings |
| Onboarding handoff | One saved packet per scope with discovery evidence, candidate reasoning, and explicit accept/reject decisions |
| Draft generation | Reviewable Ruby DSL definition carrying onboarding provenance; provider bindings still require maintainer review |
| Provider generation | Provider manifest JSON plus a provider-level manifest-review report |
| Artifact indexing | Per-scope links across discovery, handoff, reviewed definition, provider manifests, and review reports |
| Release bundling | Content-addressed `review_ready` JSON containing reviewed evidence and target artifacts |
| Bundle planning | New content-addressed `apply_ready` JSON containing embedded provider plans, transition lineage, and provider summaries |
| Exact-plan approval | `slo-rules-engine/approved-provider-plan/v1` JSON containing one target, reviewer attestation, release-bundle lineage, evidence fingerprints, managed runtime, and exact dry-run provider plan |
| Bundle execution | New content-addressed `applied` bundle with predecessor lineage and one `execution_result` artifact per target |
| Bundle verification | New content-addressed `verified` bundle with predecessor lineage and one `slo-rules-engine/bundle-target-verification/v1` artifact per target |
| Operation journal | `slo-rules-engine/provider-operation-journal/v1` JSON tied to provider, service, desired state, observed state, and plan fingerprints |
| Confirmed execution | Durable live journal transitions plus a `ProviderStateResult`; Datadog rereads backend identity/payload or delete absence, file-backed providers reread managed content, and Sloth downstream generation remains explicitly `pending` |
| Sloth downstream evidence | `slo-rules-engine/sloth-downstream-evidence/v1` linking reviewed manifest/native-input fingerprints to exact generated record and status-query identities, plus `slo-rules-engine/sloth-downstream-evidence-status/v1` freshness output |
| Live SLO status | `slo-rules-engine/live-slo-status/v1` for one manifest or `slo-rules-engine/live-slo-status-aggregate/v1` for a release/portfolio, with exact target coverage, state counts, reviewed identity/context, objective attainment, remaining budget, burn windows, provider resource names, timestamps, freshness, and machine-readable findings |
| Datadog sandbox smoke | `slo-rules-engine/datadog-sandbox-smoke/v1` JSON with public-safe read checks and optional temporary-dashboard lifecycle evidence |

### Provider Outputs

| Engineering output | `datadog` | `prometheus_stack` | `sloth` |
| --- | --- | --- | --- |
| Telemetry evidence | Active-metric or explicit query evidence normalized from Datadog APIs | Metric-name, series, or explicit PromQL evidence normalized from a Prometheus-compatible API | The Prometheus-compatible adapter, with evidence labeled for the Sloth target |
| Reviewed manifest | SLOs, burn-rate monitors, missing-telemetry monitors, decision dashboards, and route context | SLI/SLO/burn-rate recording rules, telemetry-gap and burn-rate alerts, Grafana dashboards, Alertmanager routes, and rendered native resource content | Sloth `prometheus/v1` SLO specs with event queries, page/ticket alert labels, and response annotations |
| Saved review report | `manifest-review/datadog.json` | `manifest-review/prometheus_stack.json` | `manifest-review/sloth.json` |
| Dry-run plan | API-oriented `create`, `update`, `recreate`, or `noop` changes with IDs, ownership identity, and risk | `write` or `noop` changes for `manifest.json` and every native YAML file | `write` or `noop` changes for the manifest and native Sloth input plus a `handoff` change |
| Approved exact plan | Deferred until the live backend recheck contract is verified | Immutable reviewed plan with manifest, review, handoff, desired-state, observed-state, and operation fingerprints | The same immutable contract, including the stored external-generator handoff |
| Operation journal | Confirmed apply/prune persists request method/path, returned resource ID, response fingerprint, sanitized failures, and terminal backend verification | Confirmed apply/prune persists operation attempts and terminal per-file convergence evidence | Confirmed apply/prune persists verified engine-owned file outcomes and records external-generator handoff as intentionally skipped and pending |
| Confirmed engine output | Datadog resources, durable journal, and verified `ProviderStateResult` | Managed files, durable journal, and verified `ProviderStateResult` | Verified managed manifest/input files, durable journal, `ProviderStateResult`, and pending external handoff evidence |
| Verified release output | Deferred until live bundle recheck semantics are proven | Fresh expected/actual evidence for every approved managed file and a `verified` bundle target | Fresh engine-owned file evidence plus explicit pending external-generator/downstream status |
| Downstream identity evidence | Not applicable | Generated recording-rule identities already exist in the reviewed manifest | Content-addressed reviewed mapping from current manifest/native input to saved Sloth-generated records and provider-specific status queries |
| Live status | Direct reads remain deferred; aggregate output retains the target as explicit `unsupported` coverage | GET-only reads of generated observation, evaluation-window SLO, remaining-budget, burn-rate, and timestamp records; aggregate output embeds the complete target report | Direct GET-only reads use only fresh reviewed downstream-evidence bindings for the exact manifest; aggregate output remains explicit `unsupported` coverage until evidence packaging/runtime mapping is added |
| External responsibility | Notification endpoint and credential ownership | Applying Kubernetes resources, Grafana sidecar loading, and Alertmanager receiver endpoints/credentials | Running Sloth, applying generated Prometheus rules, and configuring Alertmanager |

## Use Case 1: Find Candidate SLOs In Existing Telemetry

**Task:** inventory available service telemetry before choosing an SLI, objective, or response policy.

Datadog:

```bash
bin/rules-ctl discover-telemetry \
  --provider=datadog \
  --service=checkout-api \
  > ./work/checkout-datadog-evidence.json
```

Prometheus Stack:

```bash
bin/rules-ctl discover-telemetry \
  --provider=prometheus_stack \
  --service=checkout-api \
  --base-url=http://localhost:9090 \
  > ./work/checkout-prometheus-evidence.json
```

Sloth uses the Prometheus-compatible discovery adapter:

```bash
bin/rules-ctl discover-telemetry \
  --provider=sloth \
  --service=checkout-api \
  --base-url=http://localhost:9090 \
  > ./work/checkout-sloth-evidence.json
```

Rank one saved evidence file:

```bash
bin/rules-ctl candidates ./work/checkout-datadog-evidence.json \
  > ./work/checkout-datadog-candidates.json
```

**What to expect:**

- `discover-telemetry` writes one normalized JSON envelope to stdout; the shell redirection above creates the evidence file.
- `candidates` writes ranked proposal JSON to stdout with candidate UID, calculation basis, confidence, reasons, caveats, explanation, and rejected-signal findings.
- Datadog evidence comes from Datadog APIs. Prometheus Stack and Sloth evidence comes from a Prometheus-compatible API and retains the selected provider label.
- No definition, provider manifest, alert, dashboard, or backend resource is created.

**Intent preserved:** telemetry can support or reject a candidate, but it does not choose the objective, user journey, or operational response.

## Use Case 2: Build A Portfolio Onboarding Queue

**Task:** inspect many service scopes in one provider and leave a reusable review queue for service owners.

```bash
bin/rules-ctl discover-telemetry \
  --provider=datadog \
  --scope-file=./examples/telemetry/scopes.json \
  --output-dir=./work/discovery

bin/rules-ctl onboarding-summary \
  --handoff-dir=./work/handoff \
  ./work/discovery/index.json \
  > ./work/onboarding-summary.json
```

Review and validate one scope:

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

**What to expect:**

- Batch discovery writes one normalized JSON evidence file per scope and `./work/discovery/index.json`; runtime failures are recorded per scope.
- `onboarding-summary` writes readiness JSON to stdout and creates one rerun-safe handoff packet per scope under `./work/handoff`.
- `review-handoff` updates that packet in place and prints the updated packet; accepted/rejected decisions, notes, candidate reasoning, and original discovery evidence remain together.
- `validate-handoff` prints a validation report. `draft-from-handoff` prints Ruby DSL text; the redirection above creates the draft file with provenance comments.
- Readiness values are `ready`, `partial`, `insufficient`, or `failed`.

**Intent preserved:** a maintainer must review metric meaning, success semantics, objective, selectors, provider bindings, routes, dashboards, playbook, and miss policy before provider generation.

## Use Case 3: Discover With One Provider And Deliver Through Another

**Task:** use evidence from the backend currently deployed while generating reviewed reliability resources for a different backend.

Example: discover in Datadog, then target Prometheus Stack.

1. Run Use Cases 1 and 2 with `--provider=datadog`.
2. Add a reviewed Prometheus binding to the accepted SLI in the generated definition:

```ruby
provider_binding 'prometheus_stack' do
  metric 'http_server_request_duration_seconds_count'
  data_source 'prometheus'
  type 'counter'
  selector service: 'checkout-api'
end
```

3. Add the reviewed Alertmanager route, validate the definition, and check target telemetry:

```bash
bin/rules-ctl validate ./work/drafts/checkout-prod.rb

bin/rules-ctl reality-check \
  --provider=prometheus_stack \
  --online \
  --base-url=http://localhost:9090 \
  ./work/drafts/checkout-prod.rb
```

4. Generate the target provider manifest:

```bash
bin/rules-ctl generate \
  --provider=prometheus_stack \
  --output-dir=./work/generated \
  --handoff-dir=./work/handoff \
  ./work/drafts/checkout-prod.rb
```

**What to expect:**

- The handoff, draft, generated manifest, and review report retain Datadog as onboarding evidence provenance.
- Target validation and generation use only the explicit reviewed `prometheus_stack` binding.
- `./work/generated/checkout-api/prometheus_stack/manifest.json` contains recording rules, alerts, dashboard intent, route intent, and rendered native resource content.
- `./work/generated/manifest-review/prometheus_stack.json` links the target manifest to the reviewed handoff and fingerprints both inputs.
- The reverse flow is supported with Prometheus evidence and a reviewed Datadog binding. A definition may also contain explicit bindings for all three providers and generate one manifest per provider.

**Intent preserved:** signal kind, candidate reasoning, accepted SLO identity, objective, calculation basis, miss policy, owner, and review notes are portable. Metric names, query syntax, selectors, aggregation, histogram semantics, routes, and provider payloads are target-specific and never translated automatically.

## Use Case 4: Generate A Complete Provider Delivery Bundle

**Task:** translate one reviewed service definition into the complete artifact set owned by a selected observability provider.

```bash
bin/rules-ctl generate \
  --provider=prometheus_stack \
  --output-dir=./work/generated \
  --handoff-dir=./work/handoff \
  ./work/checkout-api.rb
```

Change `--provider` to `datadog` or `sloth` for another target.

**What to expect:**

- All providers print a JSON array of generated manifests to stdout.
- With `--output-dir`, each service manifest is saved at `./work/generated/<service>/<provider>/manifest.json`, and the provider report is saved at `./work/generated/manifest-review/<provider>.json`.
- Datadog manifests contain one SLO, burn-rate monitor, missing-telemetry monitor, and decision dashboard intent per reviewed SLO, including owner, playbook, route, and source context.
- Prometheus Stack manifests contain one base observation recording rule per SLI instance; evaluation-window success-ratio, error-ratio, objective-ratio, error-budget-ratio, `error_budget_remaining_ratio`, and window-specific burn-rate recording rules per SLO; telemetry-gap and burn-rate alerts; Grafana dashboards; Alertmanager routes; and rendered PrometheusRule/ConfigMap/route-intent content.
- Sloth manifests contain `prometheus/v1` SLO specs, error and total event queries, page/ticket alert labels, and owner/dashboard/playbook/miss-policy/route annotations.
- Generation does not write Prometheus Stack or Sloth native YAML files. Confirmed file-backed apply writes those files from the reviewed manifest.

Validate the saved report against current inputs:

```bash
bin/rules-ctl manifest-review \
  --provider=prometheus_stack \
  --manifest=./work/generated/checkout-api/prometheus_stack/manifest.json \
  --handoff-dir=./work/handoff \
  --report=./work/generated/manifest-review/prometheus_stack.json
```

**Intent preserved:** adapters render backend artifacts from reviewed neutral intent and explicit provider bindings. They do not invent telemetry, objectives, paging policy, ownership, or notification destinations.

## Use Case 5: Package A Reviewed Multi-Provider Release

**Task:** create one immutable review artifact for several provider targets, then derive read-only plans against current state.

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

bin/rules-ctl bundle create \
  --artifact-index=./work/artifact-index.json \
  --reviewer=team/payments-sre \
  --reviewed-at=2026-07-26T09:30:00Z \
  --sloth-evidence=checkout-api/sloth=./work/sloth-evidence/checkout-api.json \
  --output=./work/review-ready.json

bin/rules-ctl bundle plan ./work/review-ready.json \
  --target-backend=checkout-api/datadog=environment \
  --target-output=checkout-api/prometheus_stack=./managed \
  --target-output=checkout-api/sloth=./managed \
  --output=./work/apply-ready.json
```

**What to expect:**

- The artifact index is written to the requested file and stdout with per-scope artifact links, next actions, review validity, and freshness findings.
- `bundle create` writes and prints a content-addressed `review_ready` bundle with reviewer identity, explicit review time, source artifacts, provider targets, and no credentials. Each repeatable `--sloth-evidence=service/sloth=file` packages one already-captured, current, exact-manifest downstream evidence artifact; stale, mismatched, unknown-target, or non-Sloth mappings prevent output.
- `bundle plan` leaves the predecessor unchanged and writes/prints a new `apply_ready` bundle with a new bundle ID and predecessor lineage.
- Each provider plan is embedded as a `change_plan` artifact in `apply-ready.json`; separate plan files are not written.
- The bundle summary includes provider-level target, plan, operation, destructive, action, target, and risk counts.
- Datadog planning reads current managed API state. Prometheus Stack and Sloth planning read their configured managed directories. No mutation occurs.

**Intent preserved:** the bundle binds reviewed evidence, definition, provider manifests, review decisions, and observed-state plans without storing credentials or weakening provider-specific safety evidence.

## Use Case 6: Understand Drift Before Applying

**Task:** compare reviewed provider intent with current backend or managed-file state.

```bash
bin/rules-ctl diff \
  --provider=datadog \
  --manifest=./work/generated/checkout-api/datadog/manifest.json \
  > ./work/datadog-diff.json

bin/rules-ctl diff \
  --provider=prometheus_stack \
  --output-dir=./managed \
  --manifest=./work/generated/checkout-api/prometheus_stack/manifest.json \
  > ./work/prometheus-stack-diff.json

bin/rules-ctl diff \
  --provider=sloth \
  --output-dir=./managed \
  --manifest=./work/generated/checkout-api/sloth/manifest.json \
  > ./work/sloth-diff.json
```

**What to expect:**

- Every command prints a JSON array with one plan per manifest; the redirections above create saved diff files.
- Datadog changes are `create`, `update`, `recreate`, or `noop` and include changed paths, backend IDs, match identity, and risk when applicable.
- Datadog dashboard comparison reads the paginated custom-dashboard catalog and
  then each dashboard detail needed for managed-tag and canonical payload
  checks. Manual dashboard-list membership is not required.
- Prometheus Stack changes are `create`, `update`, or `noop` comparisons for `manifest.json` and each PrometheusRule, Grafana ConfigMap, and Alertmanager route-intent file.
- Sloth changes are `create`, `update`, or `noop` comparisons for `manifest.json` and each native Sloth input file.
- Every plan includes `slo-rules-engine/provider-state/v1` desired/observed snapshots, deterministic fingerprints, normalized changes, findings, and impact summary under `state_contract`.

**Safety boundary:** `diff` reads provider or managed-file state and never mutates it. A difference is evidence for review, not permission to apply.

## Use Case 7: Inventory Existing Managed State

**Task:** determine what the engine can match, what is missing, and what may be orphaned before adoption or cleanup.

```bash
bin/rules-ctl import \
  --provider=datadog \
  --manifest=./work/generated/checkout-api/datadog/manifest.json \
  > ./work/datadog-import.json
```

For Prometheus Stack or Sloth, change `--provider`, use that provider's manifest, and add `--output-dir=./managed`.

**What to expect:**

- The command prints a JSON array of imported-state reports; the redirection above saves the report.
- Datadog reports matched API state, missing expected resources, managed orphans, and match-identity confidence.
- Datadog discovers managed dashboards from the custom-dashboard catalog and
  full detail tags, including managed dashboards that are in no manual list.
- Prometheus Stack reports the current managed manifest and every expected native YAML file, including missing-file findings.
- Sloth reports the current managed manifest and every expected native input, including missing-input findings.
- Every report includes versioned desired state, observed state, deterministic fingerprints, and normalized findings under `state_contract`.

**Safety boundary:** import is observational. It does not claim adoption, change ownership tags, update resources, or delete orphans.

## Use Case 8: Create An Auditable Operation Journal

**Task:** persist the identity and safety requirements of one dry-run provider plan before execution behavior is added.

Create a single-manifest plan:

```bash
bin/rules-ctl apply \
  --provider=prometheus_stack \
  --dry-run \
  --output-dir=./managed \
  --manifest=./work/generated/checkout-api/prometheus_stack/manifest.json \
  > ./work/prometheus-stack-plan.json
```

Create and inspect its journal:

```bash
bin/rules-ctl journal create \
  ./work/prometheus-stack-plan.json \
  --output=./work/prometheus-stack-journal.json

bin/rules-ctl journal status \
  ./work/prometheus-stack-journal.json
```

**What to expect:**

- `journal create` accepts exactly one valid `dry_run` provider plan, verifies its nested desired-state, observed-state, and plan fingerprints, writes the initial journal atomically, and prints the same JSON.
- Repeating creation with the same plan and output is idempotent. Different content at the output path is rejected without overwrite.
- The journal ID is deterministic and tied to provider, service, plan fingerprint, desired-state fingerprint, observed-state fingerprint, and static operation identity.
- Actionable entries start `pending`; `noop` entries start `skipped`. The schema permits `pending`, `running`, `succeeded`, `failed`, and `skipped` entry states.
- Datadog entries retain backend resource IDs, match identity, changed paths, desired/observed payloads, and risk. Prometheus Stack entries retain managed-file changes and file-state verification requirements. Sloth adds external-generator handoff verification.
- `journal status` prints effective state, entry counts, resume eligibility, and findings such as `partial_failure`, `resume_blocked`, or `resume_state_recheck_required`.
- Confirmed apply/prune for every provider creates a separate live-mode journal automatically through `--journal-dir`; operators do not manually transition that journal.

**Safety boundary:** standalone `journal create` and `journal status` never execute operations. Confirmed live commands update and verify their own journal while executing. The approved-plan workflow below adds exact file-backed execution, completed replay, and explicit resume. There is no manual journal transition command, automatic retry, Datadog exact execution, or automatic rollback. Downstream Sloth verification is a separate opt-in read-only bundle transition.

## Use Case 9: Approve And Execute An Exact File-Backed Plan

**Task:** separate plan review from mutation and prove that execution uses the
reviewed operations rather than a newly generated operation list.

Start from the `apply_ready` bundle produced in Use Case 5. Approve one
Prometheus Stack target:

```bash
bin/rules-ctl plan approve ./work/apply-ready.json \
  --target=checkout-api/prometheus_stack \
  --reviewer=team/payments-sre \
  --reviewed-at=2026-07-27T14:00:00Z \
  --note='Managed-file changes reviewed.' \
  --output=./work/approved-prometheus-stack-plan.json

bin/rules-ctl plan status \
  ./work/approved-prometheus-stack-plan.json
```

Execute the approved operations:

```bash
bin/rules-ctl plan apply \
  ./work/approved-prometheus-stack-plan.json \
  --confirm \
  --journal-dir=./work/journals
```

After inspecting a partial journal and fixing the external file-write cause:

```bash
bin/rules-ctl plan resume \
  ./work/approved-prometheus-stack-plan.json \
  --confirm \
  --journal-dir=./work/journals
```

For Sloth, approve `checkout-api/sloth` into a separate output file and run the
same `plan apply` command.

**What to expect:**

- `plan approve` accepts one valid `apply_ready` bundle and one
  `manifest_bundle` or `external_generator` target. It rechecks bundle schema,
  identity, embedded fingerprints, and current source freshness before writing
  anything.
- The output file is immutable, idempotent for identical approval content, and
  uses schema `slo-rules-engine/approved-provider-plan/v1`. Conflicting content
  at the same output path returns `approved_plan_output_conflict`.
- The approved artifact contains reviewer identity, explicit ISO 8601 approval
  time, notes, source bundle ID, target identity, bundle review content and
  fingerprint, provider manifest/review-report/handoff fingerprints, exact
  provider plan, and managed output directory. Credential-like keys are
  rejected.
- `plan status` verifies the approved-plan ID, every nested provider-state
  fingerprint, evidence references, runtime path containment, and provider
  coverage without reading provider state.
- `plan apply` acquires a nonblocking lock for the selected managed
  service/provider scope and regenerates a dry-run plan only to compare its
  fingerprint with the approved plan. The regenerated operations are discarded.
- If managed-file state changed after approval, stdout contains
  `stale_approved_plan` with expected and actual plan/observed-state
  fingerprints. No operation journal JSON or managed-file mutation occurs.
- If another exact apply holds the same scope lock, stdout contains
  `approved_plan_scope_busy`; execution does not start.
- Reapplying a completed plan first proves current files still converge, then
  returns `execution.replay.status: completed`, the existing journal/result,
  and `mutated: false` without rewriting managed files.
- A partial, failed, or otherwise non-successful journal returns
  `approved_plan_requires_resume` without adding attempts. The original failed
  result includes manual rollback guidance and requires a state refresh.
- `plan resume` requires the same approved plan and journal directory. It
  verifies every prior success is still `noop`, retries only `write` entries
  whose journal resume policy is eligible, preserves earlier attempts, and
  records matched state-recheck evidence on each new attempt.
- Previously skipped writes caused by `prior_operation_failed` are executed in
  order after the failed write succeeds. A currently converged resumable write
  is recorded as reconciled by state recheck without rewriting it.
- A Sloth external-generator handoff skipped after an earlier write failure is
  not misclassified as a retryable write; resume repairs eligible engine-owned
  files and leaves the handoff explicitly external.
- Resume rechecks verification evidence for every engine-owned entry. Success
  returns `execution.resume.status: completed`, the original journal path, full
  attempt history, and a converged `ProviderStateResult`.
- Missing journals return `approved_plan_resume_not_found`. Drift in any prior
  success returns `stale_approved_plan` before a new attempt. Non-resumable or
  active entries return `approved_plan_resume_blocked`.
- On success, Prometheus Stack writes the approved manifest and native
  PrometheusRule, Grafana ConfigMap, and Alertmanager route-intent files. Sloth
  writes the approved manifest and native `prometheus/v1` input.
- Successful stdout is one live provider plan containing
  `execution.approved_plan`, `execution.operation_journal`, and
  `execution.result`. The journal validates both the live execution-plan
  fingerprint and the approved dry-run plan ID/fingerprint.
- Sloth still marks the stored external-generator handoff `skipped` with
  `external_handoff_required`; engine-owned verification can succeed while
  downstream status remains `pending`.
- Datadog targets return `unsupported_exact_plan_provider` at approval. Normal
  Datadog `apply`/`prune` remains available, but exact execution waits for
  verified live backend recheck semantics.

**Safety boundary:** source files changing after approval do not silently alter
the locked operation payload; a new release bundle and approval are required to
adopt those changes. Managed-state drift blocks execution. This workflow does
not implement automatic rollback execution, Datadog exact apply/resume, retry
of non-resumable operations, Sloth execution, Kubernetes apply, Grafana
loading, or Alertmanager delivery.

## Use Case 10: Apply And Verify An Approved Multi-Target File Release

**Task:** execute every reviewed file-backed target from one `apply_ready`
bundle, then prove its current engine-owned files still match the approved
release without rewriting them.

Use a file-only `apply_ready` bundle containing Prometheus Stack and Sloth
targets. The Datadog-inclusive bundle in Use Case 5 demonstrates packaging and
planning; it is deliberately ineligible for file-backed bundle apply.

Create one approved plan per target from the same bundle:

```bash
bin/rules-ctl plan approve ./work/apply-ready.json \
  --target=checkout-api/prometheus_stack \
  --reviewer=team/payments-sre \
  --reviewed-at=2026-07-27T14:00:00Z \
  --output=./work/approved-prometheus-stack-plan.json

bin/rules-ctl plan approve ./work/apply-ready.json \
  --target=checkout-api/sloth \
  --reviewer=team/payments-sre \
  --reviewed-at=2026-07-27T14:00:00Z \
  --output=./work/approved-sloth-plan.json
```

Apply the file-only bundle:

```bash
bin/rules-ctl bundle apply ./work/apply-ready.json \
  --confirm \
  --approved-plan=./work/approved-prometheus-stack-plan.json \
  --approved-plan=./work/approved-sloth-plan.json \
  --journal-dir=./work/journals \
  --output=./work/applied.json

bin/rules-ctl bundle status ./work/applied.json

bin/rules-ctl bundle verify ./work/applied.json \
  --sloth-evidence=checkout-api/sloth=./work/sloth-evidence/checkout-api.json \
  --target-base-url=checkout-api/sloth=http://localhost:9090 \
  --max-age-seconds=300 \
  --output=./work/verified.json

bin/rules-ctl bundle status ./work/verified.json
```

**What to expect:**

- Before execution, the command revalidates the `apply_ready` bundle, source
  freshness, exact target coverage, source bundle ID, target identity, bundle
  review, manifest/review/handoff fingerprints, and provider-plan fingerprint.
- Missing, duplicate, or unknown approvals return
  `incomplete_approved_plan_coverage`. Mismatched approval evidence returns
  `approved_plan_bundle_mismatch`. No target journal, managed file, or applied
  bundle is written.
- A Datadog or mixed live/file bundle returns
  `unsupported_bundle_apply_target` before any target execution.
- Targets execute in stable target-UID order through `ExactPlanExecutor`.
  Prometheus Stack writes its reviewed manifest and native rules/dashboard/route
  files. Sloth writes its reviewed manifest and native `prometheus/v1` input;
  downstream Sloth/Prometheus execution remains external.
- Success writes and prints a new content-addressed `applied` bundle. The
  predecessor stays byte-for-byte unchanged. Each target references a generated
  `execution_result` artifact containing
  `slo-rules-engine/bundle-target-execution/v1`, its approved-plan reference,
  durable operation-journal reference, and terminal `ProviderStateResult`.
- New execution artifacts also preserve the approved managed runtime and full
  terminal journal fingerprint, allowing later verification to reject a
  replaced or edited journal rather than trusting its path alone.
- The applied summary includes `execution_count`, `executions_by_status`, and
  provider execution rollups. `bundle status` reports `valid: true` and
  `effective_lifecycle: applied`.
- Repeating the command with the same bundle, approvals, journal directory, and
  output rechecks convergence, reuses terminal journals/results, leaves managed
  file modification times unchanged, and returns the same applied bundle ID and
  bytes.
- An incompatible existing `--output` returns
  `release_bundle_output_conflict` before target execution and is never
  overwritten.
- If a target returns `partial`, `failed`, or another non-success status, stdout
  contains `bundle_target_execution_incomplete`, the failed `target_uid`, its
  journal reference, and `completed_targets` for earlier successes. Execution
  stops, later targets do not start, and `applied.json` is not written.
- After reviewing and correcting the external cause, run `plan resume` for the
  failed approved plan. Rerun `bundle apply`; earlier completed targets replay
  without writes and the applied successor is persisted once all targets are
  terminally successful.
- `bundle verify` first validates the `applied` schema and identity, source
  freshness, `apply` lineage, all target/execution references, approved-plan
  and provider-plan fingerprints, full terminal journals, result fingerprints,
  exact journal-entry coverage, and managed runtime containment. Any invalid
  input returns `invalid_bundle_verification_inputs` before a managed-file read.
- Verification reads each approved engine-owned JSON/YAML file in stable target
  and journal-entry order. When current Sloth evidence and a runtime are
  supplied, it also performs the same eight GET-only Prometheus instant queries
  used by direct status. It performs no file, journal, Sloth, Kubernetes,
  Grafana, Alertmanager, notification, or backend write.
- Success writes and prints an immutable content-addressed `verified` successor.
  Each target references a `target_verification` artifact containing
  `slo-rules-engine/bundle-target-verification/v1`, its approved runtime/plan/
  journal identity, fresh expected and actual fingerprints, resource evidence,
  and `engine_owned_status: succeeded`. Summary output includes verification
  counts by status.
- Prometheus Stack verification is fully `succeeded`. Without an explicit
  Sloth runtime, Sloth remains `status: pending` and
  `external_status: pending` with `confirm_external_generator_completion` and
  `refresh_downstream_provider_state` requirements. With an explicit runtime,
  current exact evidence, and complete unambiguous live bindings, the verified
  successor packages that evidence plus the full neutral live-status report and
  sets `external_status: succeeded`. The runtime URL is never persisted.
- `healthy`, `at_risk`, and `exhausted` all prove that reviewed downstream
  generated state is readable; the latter two remain visible in the embedded
  status report. `missing_telemetry` or `unverifiable` returns
  `bundle_target_verification_failed` and writes no successor.
- A missing, unreadable, or changed engine-owned file returns
  `bundle_target_verification_failed`, its target UID, and stable managed-file
  findings. `verified.json` is not written.
- Datadog and mixed live/file bundles return
  `unsupported_bundle_verify_target` before journal or managed-file reads.
  Stale/mismatched evidence, incomplete target/runtime mapping, and unsafe base
  URLs also fail before managed reads or client construction. An incompatible
  existing output returns `release_bundle_output_conflict` before managed reads
  and is never overwritten.
- Verification keeps `applied.json`, journals, and managed-file modification
  times unchanged. Engine-only replay with the same compatible output rechecks
  state using the original evidence timestamp and returns identical successor
  bytes. A later live downstream snapshot should use a new output path because
  status values and sample timestamps are immutable evidence.

**Safety boundary:** bundle apply never replans an alternative operation list.
It accepts only file-backed exact plans from the same source bundle, performs
all approval/output compatibility checks before the first target, stops at the
first incomplete target, and never retries a partial plan implicitly. Bundle
verification consumes only the applied evidence, current engine-owned file
state, explicitly supplied Sloth evidence, and read-only live query results. It
turns pending external work into success only when every reviewed binding is
readable and current; it never treats SLO health as configuration convergence.
Neither transition supports live API mutation targets, automatic rollback,
Sloth execution, Kubernetes apply, Grafana loading, or Alertmanager delivery.

## Use Case 11: Apply Reviewed State

**Task:** converge current provider state after reviewing the current manifest and evidence gates.

Datadog:

```bash
bin/rules-ctl apply \
  --provider=datadog \
  --confirm \
  --journal-dir=./work/journals \
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
  --journal-dir=./work/journals \
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
  --journal-dir=./work/journals \
  --manifest=./work/generated/checkout-api/sloth/manifest.json
```

**What to expect:**

- Datadog creates, updates, or recreates SLO, monitor, telemetry-gap monitor, and dashboard API resources. Weak-ownership mutations are blocked before a journal is created.
- Prometheus Stack writes only changed `manifest.json`, PrometheusRule YAML, Grafana dashboard ConfigMap YAML, and Alertmanager route-intent YAML files below `./managed/<service>/prometheus_stack`.
- Sloth writes only changed `manifest.json` and native Sloth input YAML below `./managed/<service>/sloth`; it does not run Sloth or apply downstream rules.
- Every provider prints the immediate live-mode plan plus `execution.operation_journal` and `execution.result`.
- Each journal is saved at `./work/journals/<service>/<provider>/<journal-id>.json`.
- Successful Datadog attempts record the returned or existing `provider_resource_id`, request method/path, response fingerprint, and response top-level keys. Raw responses and raw backend error messages are not persisted.
- After Datadog mutation, the engine rereads backend state once and compares canonical payload plus provider resource identity. Missing resources, identity mismatch, payload drift, delete survival, or refresh failure produce stable verification findings and a nonzero result.
- Datadog dashboard readback uses the paginated custom-dashboard catalog plus
  full detail reads, so a newly created dashboard does not need manual-list
  membership to pass convergence verification.
- Successful file-backed attempts record the managed path as `provider_resource_id`; failed attempts record a public-safe error class, code, and message.
- Confirmed execution stops after the first failed operation, marks untouched actionable operations `skipped`, emits `failed` or `partial`, and exits nonzero.
- After execution, every attempted engine-owned file is parsed again and compared with the live plan. Journal verification evidence contains a timestamp, expected presence/content fingerprint, actual presence/content fingerprint, and stable finding codes for missing, unreadable, unexpectedly present, or mismatched files.
- Prometheus Stack reports verification `succeeded` only when every attempted managed file matches. A mismatch adds `post_apply_verification_failed`, makes the provider result `failed` when execution otherwise succeeded, and exits nonzero.
- An all-`noop` apply reports verification `not_required` because the live plan already observed matching provider or file state immediately before execution.
- Sloth records its external-generator `handoff` as `skipped` with reason `external_handoff_required` after writing engine-owned files.
- Sloth reports `engine_owned_status: succeeded` after its manifest and native inputs verify, while overall and external verification remain `pending` until the operator runs Sloth and verifies downstream Prometheus state.

**Safety boundary:** current apply replans immediately before mutation and requires reviewed manifest input. Datadog verification covers the supported managed API payload and identity contract, while file verification covers engine-owned paths. It does not prove notification delivery, Kubernetes application, Grafana loading, Alertmanager receiver delivery, Sloth execution, automatic resume, or execution of a separately approved exact plan.

## Use Case 12: Remove Managed State

**Task:** inspect and explicitly remove provider state managed for the reviewed service scope.

Start with dry-run:

```bash
bin/rules-ctl prune \
  --provider=datadog \
  --dry-run \
  --manifest=./work/generated/checkout-api/datadog/manifest.json \
  > ./work/datadog-prune-plan.json
```

Confirmed Datadog prune uses `--confirm`, `--journal-dir`, and current handoff/report evidence:

```bash
bin/rules-ctl prune \
  --provider=datadog \
  --confirm \
  --journal-dir=./work/journals \
  --manifest=./work/generated/checkout-api/datadog/manifest.json \
  --review-report=./work/generated/manifest-review/datadog.json
```

Confirmed Prometheus Stack or Sloth prune also requires `--output-dir`:

```bash
bin/rules-ctl prune \
  --provider=prometheus_stack \
  --confirm \
  --output-dir=./managed \
  --journal-dir=./work/journals \
  --manifest=./work/generated/checkout-api/prometheus_stack/manifest.json \
  --review-report=./work/generated/manifest-review/prometheus_stack.json
```

**What to expect:**

- Dry-run prints a JSON plan and does not delete anything.
- Datadog plans managed orphan deletes with provider resource ID, ownership confidence, and risk; confirmed prune rejects weak service-scope ownership.
- Prometheus Stack plans/deletes the reviewed manifest and the expected native PrometheusRule, Grafana, and route-intent files.
- Sloth plans/deletes the reviewed manifest and native Sloth input files.
- Datadog confirmed stdout includes the live plan, durable journal reference, per-delete API request evidence, deleted provider IDs, and a `ProviderStateResult`.
- Datadog rereads the managed service scope once after deletion and verifies each recorded ID is absent. A surviving resource produces `backend_resource_present_after_delete`.
- Prometheus Stack and Sloth confirmed stdout include the live plan, durable journal reference, per-delete attempts, managed path identifiers, and `ProviderStateResult`.
- A deletion failure stops later deletes, persists `failed` or `partial`, and exits nonzero.
- Every attempted delete is rechecked for absence. Remaining files record `managed_file_present_after_delete`, fail verification, and keep the command nonzero.

**Safety boundary:** deletion is limited by the reviewed service/provider scope and provider ownership gates. Verification proves Datadog managed-ID absence or engine-owned path absence only; journaling does not provide rollback, automatic resume, or downstream-system cleanup.

## Use Case 13: Verify Telemetry Before Production Adoption

**Task:** prove that each reviewed provider binding resolves to usable current evidence.

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

**What to expect:**

- The command prints JSON with provider identity, overall validity, per-service/per-SLI reports, and findings.
- Findings identify missing metrics, absent series, incomplete histogram evidence, incompatible binding semantics, or provider lookup failures.
- Datadog uses Datadog lookup semantics. Prometheus Stack and Sloth use Prometheus-compatible lookup semantics for their explicit bindings.
- A non-valid result exits nonzero and leaves definitions and provider state unchanged.

**Intent preserved:** the check tests whether reviewed intent is measurable. It reports gaps rather than changing the binding, objective, calculation basis, or SLO policy.

## Use Case 14: Generate Contextual Alert Routes

**Task:** hand alert context to a delivery system without giving the rules engine delivery credentials.

```bash
bin/rules-ctl generate-routes \
  --integration=notification_router \
  ./work/checkout-api.rb \
  > ./work/notification-routes.json
```

**What to expect:**

- The command prints a JSON array of integration manifests; the redirection above saves it.
- Datadog notification routes become Datadog route entries.
- Prometheus Stack and Sloth notification routes become Alertmanager route entries.
- Route availability-check intent is included. Endpoint URLs, tokens, receiver credentials, and message delivery outcomes are not.

**Intent preserved:** generated routes carry service, owner, severity, response, dashboard, and playbook context. The notification router remains responsible for Teams, Slack, Telegram, webhook, console, or other channel configuration and delivery.

## Use Case 15: Validate Datadog Lookup In An Isolated Sandbox

**Task:** prove the Datadog credential, dashboard catalog, detail-read, and
managed-identity contracts without using production resources.

Create a 14-day trial or approved isolated Datadog organization, create a
dedicated API key and scoped application key, then export `DD_API_KEY`,
`DD_APP_KEY`, and the region-specific `DD_SITE`. The application key needs
`dashboards_read`; add `dashboards_write` only for the mutation probe. Exact
setup steps are in [Datadog Sandbox Testing](datadog-sandbox-testing.md).

Read-only contract smoke:

```bash
scripts/datadog-sandbox-smoke \
  > /tmp/slo-rules-engine-datadog-sandbox-read.json
```

Temporary dashboard mutation smoke, only in the isolated organization:

```bash
scripts/datadog-sandbox-smoke \
  --confirm-sandbox-mutation \
  --service=slo-rules-engine-sandbox \
  > /tmp/slo-rules-engine-datadog-sandbox-mutation.json
```

Optional telemetry lookup with `metrics_read`:

```bash
bin/rules-ctl discover-telemetry \
  --provider=datadog \
  --service=slo-rules-engine-sandbox \
  > /tmp/slo-rules-engine-datadog-sandbox-telemetry.json
```

**What to expect:**

- Read-only smoke prints `slo-rules-engine/datadog-sandbox-smoke/v1` JSON with
  `mode: read_only`, passed credential/API-key/catalog checks, and either a
  passed dashboard-detail check or an `empty_catalog` skip.
- Read-only smoke performs `GET /api/v1/validate`, the first paginated custom
  dashboard catalog read, and at most one dashboard detail read. It makes no
  provider changes.
- Confirmed mutation smoke creates one uniquely tagged empty dashboard, finds
  it through catalog/detail reads by high-confidence `source_ref`, deletes it,
  verifies absence, and prints only the temporary provider ID and source
  identity.
- Mutation failures attempt cleanup. An interrupted process may require manual
  removal of the dashboard tagged `service:slo-rules-engine-sandbox`.
- Telemetry discovery prints the normal normalized evidence envelope. An empty
  trial is expected to report insufficient signals while still proving
  authenticated metric-catalog access and normalization.
- Missing credentials exit nonzero with `missing_credentials`. API failures
  expose only a stable code, error class, and HTTP status; keys, private
  dashboard payloads, and raw response bodies are never printed.

**Safety boundary:** the mutation flag is an operator assertion that the target
organization is disposable or explicitly approved for testing. The probe
creates no SLO, monitor, route, or telemetry and does not bypass the reviewed
manifest, journal, ownership, and verification gates of normal `apply` or
`prune`.

## Use Case 16: Review Sloth Downstream Generated Rules

**Task:** prove that Prometheus recording rules generated by an externally run
Sloth process still correspond exactly to the current reviewed Sloth manifest
and native input before using those records for status or downstream release
verification.

Run the external handoff command recorded by Sloth `plan` or `apply`, save its
Prometheus rule YAML, then capture the reviewed mapping:

```bash
bin/rules-ctl sloth-evidence capture \
  --manifest=./managed/checkout-api/sloth/manifest.json \
  --input=./managed/checkout-api/sloth/generated/sloth.yaml \
  --generated-rules=./work/sloth-output/checkout-api-rules.yaml \
  --reviewer=team/payments-sre \
  --reviewed-at=2026-08-04T12:00:00Z \
  --output=./work/sloth-evidence/checkout-api.json
```

Repeat `--input` in manifest spec order when the reviewed manifest contains
multiple `artifacts.sloth_specs` entries.

Before relying on saved evidence, recheck every recorded source:

```bash
bin/rules-ctl sloth-evidence status \
  ./work/sloth-evidence/checkout-api.json
```

**What to expect:**

- Capture stdout and `--output` contain identical
  `slo-rules-engine/sloth-downstream-evidence/v1`
  `SlothDownstreamEvidence` JSON. Its `sloth-evidence-<sha256>` identity covers
  the downstream review, current source fingerprints, exact generated record
  identities, and provider-specific status bindings.
- Every reviewed SLO includes its Sloth service/SLO/ID identity; objective,
  allowed/remaining budget, current/period burn, time-period, metadata, base
  and evaluation-window error-ratio records; exact selectors; source paths;
  and reviewed objective/evaluation-window values.
- The observation binding is the exact reviewed native
  `sli.events.total_query`. Sloth's characterized default output has no
  dedicated observation record, so the tool does not relabel an error ratio as
  request volume. Success and freshness queries derive only from the captured
  evaluation-window record inside this provider artifact.
- Capture reads one reviewed manifest, every native input, and the saved
  generated-rule YAML. Only after all checks pass does it write the explicit
  output file. It makes zero provider reads and writes, loads no credentials,
  executes no shell command, and does not run Sloth.
- Missing review provenance, mismatched native inputs, missing/ambiguous or
  unrelated recording rules, inconsistent Sloth IDs, objective/budget drift,
  credential-like keys, unsafe YAML, or malformed sources print
  `invalid_sloth_downstream_evidence`, include stable findings, exit one, and
  leave the requested output absent.
- Status stdout is one
  `slo-rules-engine/sloth-downstream-evidence-status/v1`
  `SlothDownstreamEvidenceStatus`. Fresh evidence reports every expected and
  actual fingerprint and exits zero. Semantic source drift reports `stale`,
  includes `stale_sloth_manifest`, `stale_sloth_native_input`, or
  `stale_generated_rules`, and exits one.
- Status validates the evidence schema, credential safety, and content ID
  before reading its recorded source paths. A tampered evidence document fails
  with `sloth_evidence_identity_mismatch` and does not trust those paths. A
  rehashed document whose mappings are not exactly rebuilt from the linked
  sources fails `sloth_evidence_source_derivation_mismatch`.
- This artifact closes the reviewed generated-rule identity prerequisite and
  is required by direct Sloth `status`, aggregate Sloth status, and opt-in
  downstream `bundle verify`. Evidence capture/status themselves still make no
  Prometheus call.

**Safety boundary:** PromQL names and queries remain provider evidence. The
neutral SLO objective and response policy are unchanged, and reviewer
attestation cannot authorize provider mutation.

## Use Case 17: Inspect Live SLO And Error-Budget Status

**Task:** answer whether reviewed Prometheus Stack or evidence-linked Sloth
SLOs for one service, one reviewed release, or an explicit service portfolio
are attaining their objectives, how much error budget remains, whether burn
policy is breached, and whether each target's evidence is fresh enough to
trust.

The neutral DSL carries an explicit evaluation window:

```ruby
slo do
  uid 'successful-requests'
  objective 0.999
  evaluation_window '30d'
  success_selector status: 'success'
end
```

`30d` is the compatibility default when the field is omitted. Generation
evaluates the success ratio over that window, records the allowed
`error_budget_ratio`, records the current `error_budget_remaining_ratio`, and
computes each burn-rate record from its own policy window.

Read the live generated series:

```bash
bin/rules-ctl status \
  --provider=prometheus_stack \
  --manifest=./work/generated/checkout-api/prometheus_stack/manifest.json \
  --base-url=http://localhost:9090 \
  --max-age-seconds=300 \
  --output=./work/status/checkout-api.json
```

`PROMETHEUS_URL` supplies the default base URL when `--base-url` is omitted.

For one Sloth manifest, supply the current reviewed downstream evidence and an
explicit Prometheus runtime:

```bash
bin/rules-ctl status \
  --provider=sloth \
  --manifest=./managed/checkout-api/sloth/manifest.json \
  --evidence=./work/sloth-evidence/checkout-api.json \
  --base-url=http://localhost:9090 \
  --max-age-seconds=300 \
  --output=./work/status/checkout-api-sloth.json
```

The Sloth form has no environment-derived endpoint fallback. Before client
construction it validates the evidence schema/content ID, rereads every source
fingerprint, matches the exact manifest fingerprint and service, requires
complete SLO coverage, and retains the reviewed service/SLI/instance/SLO
identity from the manifest.

Assess every readable target in one current reviewed release:

```bash
bin/rules-ctl status \
  --bundle=./work/release-bundle.json \
  --target-base-url=checkout-api/prometheus_stack=http://checkout-prometheus.example.test \
  --target-base-url=checkout-api/sloth=http://checkout-prometheus.example.test \
  --target-base-url=search-api/prometheus_stack=http://search-prometheus.example.test \
  --max-age-seconds=300 \
  --output=./work/status/release.json
```

The release bundle may also contain Datadog targets or Sloth targets without a
packaged `sloth_downstream_evidence` artifact. Do not provide runtime mappings
for those targets; the aggregate report retains them as unsupported coverage.
An evidence-backed Sloth target is readable and requires its own explicit
Prometheus-compatible runtime mapping.

For a cross-service portfolio independent of release packaging, create a
credential-free input:

```json
{
  "schema_version": "slo-rules-engine/live-status-portfolio/v1",
  "kind": "LiveStatusPortfolio",
  "targets": [
    {
      "uid": "checkout-api/prometheus_stack",
      "manifest": "../generated/checkout-api/prometheus_stack/manifest.json"
    },
    {
      "uid": "search-api/prometheus_stack",
      "manifest": "../generated/search-api/prometheus_stack/manifest.json"
    },
    {
      "uid": "checkout-api/sloth",
      "manifest": "../generated/checkout-api/sloth/manifest.json",
      "evidence": "../sloth-evidence/checkout-api.json"
    }
  ]
}
```

Then run:

```bash
bin/rules-ctl status \
  --portfolio=./work/status/portfolio.json \
  --target-base-url=checkout-api/prometheus_stack=http://checkout-prometheus.example.test \
  --target-base-url=checkout-api/sloth=http://checkout-prometheus.example.test \
  --target-base-url=search-api/prometheus_stack=http://search-prometheus.example.test \
  --output=./work/status/portfolio-report.json
```

**What to expect:**

- Single-manifest stdout is one `slo-rules-engine/live-slo-status/v1`
  `LiveSLOStatusReport`. Bundle and portfolio stdout is one
  `slo-rules-engine/live-slo-status-aggregate/v1`
  `LiveSLOStatusAggregateReport`. In every mode, `--output` writes the same
  JSON and adds its saved report path.
- The report summary counts `healthy`, `at_risk`, `exhausted`,
  `missing_telemetry`, and `unverifiable` SLOs. Each status includes reviewed
  service/SLI/instance/SLO identity, objective and evaluation window,
  attainment, allowed/remaining/consumed budget, burn windows, observations,
  source timestamp, age, freshness limit, owner, dashboard, playbook, generated
  recording-rule identifiers, provider query evidence, and findings.
- Aggregate output sorts target envelopes by `service/provider`, embeds the
  complete single-manifest report under every readable target, and adds
  `target_count`, `reported_targets`, `unsupported_targets`, `slo_count`, all
  five state counts, `coverage_complete`, and `evidence_complete`.
- The aggregate source contains the checked bundle ID/lifecycle/fingerprint or
  the loaded portfolio and manifest fingerprints. Per-target runtime URLs are
  never written to the source, target reports, saved report, release bundle, or
  portfolio.
- The reader performs eight `GET /api/v1/query` reads for the one-SLO fixture:
  observation, success, objective, allowed budget, remaining budget, two burn
  windows, and `timestamp(success_ratio)`. It performs no write, reload,
  Kubernetes, Grafana, Alertmanager, or notification call.
- The Sloth reader takes all eight expressions from
  `status_bindings` in the fresh content-addressed evidence. It does not infer
  PromQL from neutral intent, execute Sloth, reload rules, or accept a manifest
  with a different fingerprint. Its provider resources include the evidence
  ID, exact `sloth_id`, and captured recording-rule selectors.
- A fresh attained SLO with no burn breach is `healthy`; a burn breach or
  internally inconsistent below-target result is `at_risk`; zero remaining
  budget is `exhausted`; absent or stale evidence is `missing_telemetry`; and
  ambiguous, invalid, failed, or incomplete evidence is `unverifiable`.
- These five states are report data, so a successfully produced unhealthy
  report exits zero. In aggregate mode, one target's failed queries produce an
  `unverifiable` target report while successful target reports remain present
  and the command exits zero.
- Bundle mode validates bundle schema, content identity, packaged
  fingerprints, review state, and current source files before the first
  backend read. Portfolio mode validates its schema, credential-free content,
  every manifest, evidence reference, review provenance, unique UID, and exact
  `service/provider` identity before the first read. Both modes preflight every
  Sloth evidence schema/content ID, local source fingerprint and derivation,
  exact manifest/service/SLO coverage, and every runtime mapping before any
  target client is constructed.
- Missing, unknown, duplicate, unsupported-target, credential-bearing, or
  invalid runtime mappings fail before any client is created. Direct Datadog
  use fails `unsupported_live_status_provider`. Direct Sloth use fails
  `invalid_sloth_live_status_evidence` before backend access when evidence is
  missing, invalid, stale, linked to another manifest/service, or incomplete.
  A mixed aggregate retains Datadog targets and Sloth targets without evidence
  as `outcome: unsupported`, sets `coverage_complete: false`, and makes no read
  for them. Missing Sloth evidence uses
  `missing_sloth_live_status_evidence`; an all-unsupported aggregate fails
  `no_supported_live_status_targets`.
- Query failure findings retain the provider expression and error class, but
  not the raw backend error message. The report never stores credentials.
- No mode performs provider writes, configuration reloads, Kubernetes applies,
  Grafana changes, Alertmanager changes, or notification delivery.
- Datadog direct reads remain postponed. Sloth reads are available for one
  manifest and for release/portfolio targets carrying one current exact
  downstream-evidence artifact. Bundle downstream verification remains a
  separate read-only transition.

**Official Sloth MCP path:** current Sloth `main` can expose a stateless,
read-only Streamable HTTP MCP endpoint from `sloth server --mcp-enabled`. The
engine does not consume it yet. The planned provider adapter will version-gate
the upstream surface, allowlist its six read-only tools, reconcile exact
`sloth_id` values against reviewed downstream evidence, and first emit a
supplemental comparison report. MCP-only status cannot claim parity yet because
the upstream tools do not expose total observations, exact source record
selectors, or contract-equivalent sample freshness. Setup, expected outputs,
refusals, and promotion gates are in
[Official Sloth MCP Integration Path](sloth-mcp-integration.md).

**Intent preserved:** objective, evaluation window, calculation basis, and
response context come from reviewed neutral intent. Release and portfolio
aggregation preserve every target report instead of redefining or collapsing
it. PromQL record names and instant-query syntax stay in provider readers and
Sloth downstream evidence;
the neutral status model contains only normalized values, identity, freshness,
coverage, and findings.

## Use Case 18: Operate The Reviewed Workflow From An AI Agent

**Delivery status:** planned. AICLI-F1 has implemented the internal registry and
the separate Human-to-Agent command catalog, but the Agent commands and strict
schemas in this use case are not available in the current binary.

**Task:** let an AI agent discover and invoke the same reviewed onboarding,
release, provider-state, and live-status behavior as an engineer without
guessing flags, receiving unbounded output, or bypassing safety gates.

Target discovery:

```bash
bin/rules-ctl agent catalog --format=json
bin/rules-ctl agent describe bundle.verify --format=json
```

Target structured invocation:

```bash
bin/rules-ctl agent invoke bundle.verify \
  --json-file=./work/requests/verify-bundle.json \
  --fields=request_id,command_id,outcome,result.bundle_id,result.lifecycle,findings
```

Current catalog mapping entity:

```json
{
  "schema_version": "slo-rules-engine/cli-command-catalog/v1",
  "commands": [
    {
      "id": "bundle.verify",
      "human_cli": "bin/rules-ctl bundle verify ./applied.json --output=./verified.json",
      "agent_cli_json": {
        "schema_version": "slo-rules-engine/agent-command-request/v1",
        "command_id": "bundle.verify",
        "command_version": 1,
        "arguments": {
          "bundle_file": "./applied.json",
          "output_file": "./verified.json"
        }
      }
    }
  ]
}
```

The implemented catalog contains this mapping shape for all 37 commands. It is
an internal versioned parity entity, not current CLI stdout. `agent catalog`
will expose a bounded form in AICLI-F2.

The request file carries the complete versioned rules-engine command request,
including the applied bundle path, verified output path, workspace root, and
`validate_only`, plan, or execute mode where the command supports them. It does
not carry provider credentials or arbitrary provider mutation payloads.

**What to expect:**

- Current Human commands behave as before. Registry lookup adds no stdout,
  files, provider reads, provider writes, credential loading, or new exit codes.
- Developers can inspect the immutable `CommandCatalog` through the Ruby
  library. Each entry pairs `human_cli` with `agent_cli_json`; parity tests fail
  if an executable Human root or grouped subcommand is absent from the registry.
- `agent catalog` prints a bounded versioned JSON command inventory. `agent
  describe` prints request/result/error schemas, side-effect class, provider
  reads/writes, required review/approval/confirmation evidence, credential
  references, field masks, limits, streaming support, and stable refusal codes.
- `agent invoke` prints one versioned
  `slo-rules-engine/agent-command-result/v1` JSON envelope on success or one
  versioned JSON error envelope on failure. It never replaces result data with
  prose usage text.
- Inline JSON, JSON file, and stdin forms are mutually exclusive and normalize
  to the same request as the Human CLI convenience form. Equivalence tests
  prove the same domain result, provider reads/writes, refusal codes, and
  persisted artifacts.
- Unknown fields, invalid field masks, path traversal or symlink escape,
  prohibited control characters, unsafe/pre-encoded identifiers, invalid URLs,
  excessive depth/size, and credential-like request keys fail before handlers
  or provider clients are constructed.
- `validate_only` performs no file read/write, provider call, or credential
  loading. Observational planning declares any state reads. Confirmed mutation
  still requires current reviewed provenance, ownership, exact-plan evidence
  where supported, explicit confirmation, durable journal, and verification.
- Large collection results apply declared limits and cursors; eligible flows
  can emit NDJSON. Field masks are schema-checked, and truncation is explicit.
- Provider-controlled free text is sanitized before Agent CLI or MCP output.
  Rejected prompt-injection-bearing text is represented by findings and
  fingerprints, not emitted inline.
- A shipped agent skill tells agents to inspect schemas, request minimal
  fields, run validation-only first, distinguish plans from writes, obtain user
  confirmation, and keep credentials outside requests.
- The later MCP stdio surface exposes the same allowlisted command registry and
  handlers without constructing a shell command. It does not gain capabilities
  before the Agent CLI safety contract is complete.
- Existing Human CLI syntax, stdout, exit codes, provider behavior, and saved
  schema contracts remain compatible throughout rollout.

**Safety boundary:** the Agent CLI and MCP are adapters, not policy bypasses.
Raw structured requests express rules-engine commands; neutral reliability
intent, review evidence, provider validation, freshness, ownership, exact-plan,
confirmation, journal, and verification requirements remain unchanged. Until
the AICLI-F2 Agent CLI is implemented, agents must use the documented current
Human CLI and must not assume the target commands above exist.

## CLI Execution Boundary

Every command in this guide still runs through `bin/rules-ctl`. The executable
is a thin bootstrap for `lib/slo_rules_engine/cli.rb`, which composes the
command-family modules and shared manifest/state orchestration. This structural
boundary does not change any documented arguments, stdout, stderr, exit status,
written artifact, provider read, provider write, or refusal behavior.

## Maintenance Rule

Update or rewrite usage when any of these changes:

- a command is added, removed, renamed, or gains a safety gate
- a provider starts or stops generating an artifact
- a provider automation mode or state action changes
- a workflow begins contacting a backend or mutating state
- bundle lifecycle, identity, runtime configuration, or output changes
- operation-journal schema, execution, resume, or verification behavior changes
- approved-plan schema, review, locking, exact execution, replay, or provider coverage changes
- exact-plan resume eligibility, state-recheck, attempt, or re-verification behavior changes
- cross-provider evidence portability or binding requirements change
- live-status schema, classification, freshness, provider reads, or supported scope changes
- Human CLI command mapping, Agent CLI request mapping, command registry schema,
  runtime introspection, side-effect metadata, field masks/limits, agent skill,
  response sanitization, or MCP projection changes

Every CLI change must update both Human CLI and Agent CLI sub-interfaces in the
same checkpoint once Phase 14 begins; during bootstrap it must update the
parity inventory and registry mapping that will generate both. Semantics,
safety gates, provider reads/writes, and refusal behavior must remain
equivalent even when syntax or presentation differs.

Keep this guide organized around engineering tasks. Every use case must state concrete stdout, written-file, provider-read, provider-write, and refusal behavior that applies.
