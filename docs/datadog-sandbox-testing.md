# Datadog Sandbox Testing

Use an isolated Datadog organization for live provider-contract checks. The
repository never needs credentials in source files, fixtures, release bundles,
or saved smoke reports.

## Obtain An Isolated Organization

Choose one path:

1. **General development:** create a
   [14-day Datadog trial](https://www.datadoghq.com/free-datadog-trial/).
   Datadog states that no credit card is required. Select the data region
   carefully because the site determines `DD_SITE`.
2. **Datadog Technology Partner:** request a dedicated developer sandbox in the
   Datadog Partner Portal. Datadog documents a one-to-two-business-day
   provisioning window in
   [Build a Marketplace Offering](https://docs.datadoghq.com/extend/integrations/marketplace_offering/).
3. **Existing customer:** ask the Datadog administrator or account team for an
   isolated organization approved for temporary API mutations. Do not point the
   mutating smoke test at the production organization.

The free trial is the shortest public path for this project. A dedicated
partner sandbox is the longer-lived path when partner eligibility applies.

## Create Least-Privilege Credentials

In the sandbox organization:

1. Open **Organization Settings > API Keys**, create a dedicated key, and copy
   it.
2. Open **Organization Settings > Application Keys**, create a dedicated scoped
   key, and copy it immediately.
3. Grant `dashboards_read` for the read-only smoke test.
4. Add `dashboards_write` only for the temporary create/find/delete smoke test.
5. Add `metrics_read` only when running telemetry discovery or online reality
   checks.

Datadog's
[API and Application Keys](https://docs.datadoghq.com/account_management/api-app-keys/)
documentation recommends least privilege and states that new organizations use
one-time-read application-key secrets. Store the values in a secret manager or
an ephemeral shell environment, never in this repository.

Select the site that matches the signup region. Common examples:

| Datadog site | `DD_SITE` |
| --- | --- |
| US1 | `datadoghq.com` |
| EU1 | `datadoghq.eu` |
| US3 | `us3.datadoghq.com` |
| US5 | `us5.datadoghq.com` |
| AP1 | `ap1.datadoghq.com` |
| AP2 | `ap2.datadoghq.com` |

In `zsh`, load secrets without putting their values in shell history:

```zsh
read -s "DD_API_KEY?Datadog sandbox API key: "
echo
export DD_API_KEY

read -s "DD_APP_KEY?Datadog sandbox application key: "
echo
export DD_APP_KEY

export DD_SITE=datadoghq.eu # Replace with the selected Datadog site.
```

Allow a few seconds after creating keys before testing. Datadog documents
eventual consistency for new and revoked keys.

## Run The Read-Only Contract Smoke

```bash
scripts/datadog-sandbox-smoke \
  > /tmp/slo-rules-engine-datadog-sandbox-read.json
```

Expected provider reads:

```text
GET /api/v1/validate
GET /api/v1/dashboard?count=100&start=0
GET /api/v1/dashboard/{dashboard_id} # only when the catalog is non-empty
```

Expected output:

- `slo-rules-engine/datadog-sandbox-smoke/v1` JSON
- `status: passed` and `mode: read_only`
- passed credential, API-key, and dashboard-catalog checks
- a passed dashboard-detail check, or `skipped` with `empty_catalog`
- `mutation.status: not_requested`

The output contains no credentials, dashboard titles, dashboard payloads, or
raw Datadog error bodies. An empty trial organization is a valid partial test:
it proves key-pair authorization and the custom-dashboard catalog contract but
cannot prove detail shape until a dashboard exists.

## Run The Temporary Dashboard Mutation Smoke

Run this only in the isolated organization:

```bash
scripts/datadog-sandbox-smoke \
  --confirm-sandbox-mutation \
  --service=slo-rules-engine-sandbox \
  > /tmp/slo-rules-engine-datadog-sandbox-mutation.json
```

Expected provider changes:

- create one empty dashboard with a unique title
- tag it with `managed_by:slo-rules-engine`,
  `service:slo-rules-engine-sandbox`, and a unique `source_ref`
- find it through the paginated custom-dashboard catalog and full detail reads
- require a high-confidence `source_ref` identity match
- delete it and verify it disappears from reconciled dashboard state

Expected output:

- `status: passed` and `mode: temporary_dashboard_mutation`
- the temporary Datadog dashboard ID and generated `source_ref`
- checks for create, source-ref reconciliation, delete, and confirmed absence

The command attempts cleanup if reconciliation fails after creation. If the
process is interrupted, search the sandbox dashboard catalog for
`service:slo-rules-engine-sandbox` and remove the temporary dashboard manually.

This is a narrow provider-contract probe, not a replacement for reviewed
`apply`/`prune`. It intentionally does not create SLOs, monitors, notification
routes, or telemetry.

## Exercise Telemetry Lookup

With `metrics_read` on the application key:

```bash
bin/rules-ctl discover-telemetry \
  --provider=datadog \
  --service=slo-rules-engine-sandbox \
  > /tmp/slo-rules-engine-datadog-sandbox-telemetry.json
```

An empty trial normally produces normalized evidence with no usable service
signals and explicit insufficiency findings. That still proves authentication,
metric-catalog access, normalization, and the read-only discovery boundary.
Testing candidate quality or online reality checks requires representative
test telemetry and remains a separate checkpoint.

## Revoke And Verify

After testing:

1. Revoke the dedicated application key.
2. Revoke the dedicated API key if it is not used by another sandbox workflow.
3. Unset local variables:

```bash
unset DD_API_KEY DD_APP_KEY DD_SITE
```

No live sandbox result is committed. Public-safe request/response shapes are
captured separately in [Datadog Public Contract Evidence](datadog-contract-evidence.md).
