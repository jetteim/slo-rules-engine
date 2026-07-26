# Prometheus Stack Bundle Walkthrough

This walkthrough uses a public-safe reviewed fixture and only manages local files. It does not contact Kubernetes, Prometheus, Grafana, Alertmanager, or the notification router.

## Scope And Safety

Target:

- one reviewed `checkout-api` Prometheus Stack manifest
- one Prometheus Operator `PrometheusRule`
- one Grafana sidecar dashboard `ConfigMap`
- one Alertmanager route-intent document

Blast radius:

- files below `<output-dir>/checkout-api/prometheus_stack`
- no direct backend or cluster mutation
- no receiver URL, secret, token, or credential generation

Rollback:

- reapply the last reviewed manifest to restore managed-file drift
- use a previously reviewed manifest to roll back desired content
- use reviewed `prune --confirm` to remove the complete local bundle

The route-intent document leaves `receiver_contract.configuration_required` set to `true`. A downstream deployment owner must configure the notification-router webhook host and credentials.

## Generate And Review

```bash
tmpdir="$(mktemp -d)"
generated_dir="$tmpdir/generated"
managed_dir="$tmpdir/managed"
journal_dir="$tmpdir/journals"
definition="./examples/prometheus-stack/reviewed-checkout.rb"

bin/rules-ctl validate "$definition"

bin/rules-ctl generate \
  --provider=prometheus_stack \
  --output-dir="$generated_dir" \
  "$definition"

manifest="$generated_dir/checkout-api/prometheus_stack/manifest.json"
report="$generated_dir/manifest-review/prometheus_stack.json"

bin/rules-ctl manifest-review \
  --provider=prometheus_stack \
  --manifest="$manifest" \
  --report="$report"
```

The saved report must be valid and fresh before confirmed apply.

## Plan And Apply

Plan without writing files:

```bash
bin/rules-ctl apply \
  --provider=prometheus_stack \
  --dry-run \
  --output-dir="$managed_dir" \
  --manifest="$manifest"
```

The plan contains four `write` operations: `manifest.json`, `prometheus-rules.yaml`, `grafana-dashboards.yaml`, and `alertmanager-routes.yaml`.

Write the reviewed local bundle:

```bash
bin/rules-ctl apply \
  --provider=prometheus_stack \
  --confirm \
  --output-dir="$managed_dir" \
  --journal-dir="$journal_dir" \
  --manifest="$manifest" \
  --review-report="$report"
```

The generated files are:

```text
<managed-dir>/checkout-api/prometheus_stack/manifest.json
<managed-dir>/checkout-api/prometheus_stack/generated/prometheus-rules.yaml
<managed-dir>/checkout-api/prometheus_stack/generated/grafana-dashboards.yaml
<managed-dir>/checkout-api/prometheus_stack/generated/alertmanager-routes.yaml
```

Stdout also contains `execution.operation_journal.path` and a
`ProviderStateResult`. The journal records four successful write attempts and
the result records each managed path as `provider_resource_id`.
`verification.status` remains `pending` until post-apply state refresh is
implemented.

## Verify And Reconcile

Confirm the managed state matches the reviewed manifest:

```bash
bin/rules-ctl diff \
  --provider=prometheus_stack \
  --output-dir="$managed_dir" \
  --manifest="$manifest"

bin/rules-ctl import \
  --provider=prometheus_stack \
  --output-dir="$managed_dir" \
  --manifest="$manifest"
```

A clean `diff` reports four `noop` operations. A complete `import` reports an empty `findings` array and returns the three parsed native bundle files beside the managed manifest.

When a managed YAML file drifts, `diff` identifies its exact changed paths.
Re-running the confirmed apply with `--journal-dir="$journal_dir"` rewrites only
the drifted file; unchanged files remain `noop`. A write failure persists
`failed` or `partial`, skips later writes, and exits nonzero.

## Prune

Review the delete plan with `--dry-run`, then remove the local bundle:

```bash
bin/rules-ctl prune \
  --provider=prometheus_stack \
  --dry-run \
  --output-dir="$managed_dir" \
  --manifest="$manifest"

bin/rules-ctl prune \
  --provider=prometheus_stack \
  --confirm \
  --output-dir="$managed_dir" \
  --journal-dir="$journal_dir" \
  --manifest="$manifest" \
  --review-report="$report"
```

Confirmed prune records one delete attempt per managed path in a separate
operation journal. There is no automatic rollback, resume, or post-delete
verification.

The automated verification for this flow is:

```bash
ruby -Ilib test/prometheus_stack_walkthrough_test.rb
```
