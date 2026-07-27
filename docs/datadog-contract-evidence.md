# Datadog Public Contract Evidence

This log records the public API evidence used to support Datadog reconciliation
behavior. It does not contain organization data, credentials, raw private
responses, or inferred provider semantics.

## Dashboard Catalog Readback

Evidence reviewed on 2026-07-27:

- [Datadog Dashboards API](https://docs.datadoghq.com/api/latest/dashboards/)
  exposes `GET /api/v1/dashboard` for all custom-created or cloned dashboards.
- [Get a dashboard](https://docs.datadoghq.com/api/latest/dashboards/get-a-dashboard/)
  exposes `GET /api/v1/dashboard/{dashboard_id}` for the full dashboard,
  including tags and widgets.
- [Datadog dashboard authorization scopes](https://docs.datadoghq.com/api/latest/scopes/)
  lists both reads under `dashboards_read`.
- Dashboard-list membership is managed by separate Dashboard Lists endpoints
  and is not used as managed-resource identity.

Verified engine contract:

- list active custom dashboards with `count=100` and an incrementing `start`
  offset until the returned page is shorter than 100 entries
- read each returned dashboard by ID before evaluating managed tags
- match desired dashboards by the engine-managed `source_ref` tag first
- permit title fallback only for explicitly engine-managed dashboards
- discover service-scoped managed dashboards whether or not they belong to a
  manual dashboard list
- preserve duplicate `source_ref` or title matches as low-confidence ambiguous
  identity

Public-safe fixtures:

- `test/fixtures/datadog/dashboard_catalog_page.json`
- `test/fixtures/datadog/dashboard_detail.json`
- `test/datadog_client_state_test.rb`

Expected provider reads:

```text
GET /api/v1/dashboard?count=100&start=0
GET /api/v1/dashboard/{dashboard_id}
GET /api/v1/dashboard?count=100&start=100
```

The second catalog page is read only when the first contains 100 entries.

## Evidence Limits

- No private Datadog organization was contacted for this checkpoint.
- The fixtures characterize documented request and response fields only.
- Provider rate limits, organization-specific permissions, and undocumented
  response fields remain outside the verified contract.
- SLO, monitor, and dashboard mutation semantics not represented by a public
  fixture remain open Phase 11 work.
