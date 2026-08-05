# Official Sloth MCP Integration Path

This document records how the rules engine can consume Sloth's own MCP server
without confusing it with the separate MCP server planned for `rules-ctl`.

## Verified Upstream Surface

The official [`slok/sloth`](https://github.com/slok/sloth) repository was
checked at main revision
[`8a3be4fab79defa4448d09d91b48422615980b05`](https://github.com/slok/sloth/commit/8a3be4fab79defa4448d09d91b48422615980b05)
on 2026-08-05. That revision contains a stateless Streamable HTTP MCP handler
implemented with the official Go MCP SDK.

Sloth starts it as part of the application server:

```bash
sloth server \
  --mcp-enabled \
  --mcp-path=/mcp \
  --app-listen-address=127.0.0.1:8080 \
  --prometheus-address=http://localhost:9090
```

The MCP endpoint is `http://127.0.0.1:8080/mcp`. The code declares six
read-only tools:

| Tool | Output useful to this engine |
| --- | --- |
| `context` | Running Sloth version and framework description |
| `list_services` | Service IDs, SLO counts, over-budget counts, and alert rollups with pagination |
| `list_slos` | Sloth/SLO identity, objective, period, current burn, period budget consumption, and alert state with pagination |
| `get_slo` | One SLO's current objective, period, burn, budget, and alert state |
| `get_slo_burned_budget_range` | Current/expected remaining budget plus compressed time series |
| `get_slo_sli_availability_range` | Compressed availability series with start time and step |

The latest tagged Sloth release observed during the check was `v0.16.0`,
published before the MCP commits. Until an official release contains this
surface, consumers must treat it as main-branch-only and version-gate it.

## Two Different MCP Boundaries

The official Sloth MCP server is a **provider runtime**. It reads Sloth's
Prometheus-backed operating view and can become an optional input adapter.

The planned `rules-ctl` MCP stdio server in AICLI-F6 is an **engine command
interface**. It will project the same reviewed commands and safety gates as the
Human and Agent CLIs. It must not reimplement Sloth tools or call provider
payload paths directly.

An engine MCP `status` tool may eventually select the Sloth MCP runtime adapter,
but it must still invoke the shared `status` handler and all downstream-evidence
preflights.

## Capability Path

### 1. Contract-complete direct status

The implemented Sloth reader remains the authoritative baseline. It requires
fresh `slo-rules-engine/sloth-downstream-evidence/v1`, reconciles every SLO by
exact reviewed identity, and queries only the recorded Prometheus expressions.
This preserves observations, exact recording-rule identities, sample
freshness, and provider-query evidence in the neutral status report.

### 2. Read-only MCP discovery and cross-check

Add an optional provider adapter that:

1. accepts an explicit HTTP(S) MCP endpoint only at runtime
2. performs MCP initialization and `tools/list` before domain calls
3. requires the exact allowlisted read-only tool inventory and validates every
   result against a pinned schema
4. calls `context` and checks the running Sloth version against a tested
   capability matrix
5. uses `list_slos` with service filtering and bounded cursor traversal, then
   matches every reviewed evidence entry by exact `sloth_id`
6. rejects missing, duplicate, grouped, or unexpected identity matches
7. compares MCP objective and period with reviewed manifest/evidence values
8. optionally calls `get_slo` and both range tools for supplemental current and
   historical evidence
9. emits a provider-specific comparison report linked to the evidence ID and
   manifest fingerprint, without persisting the runtime endpoint

This first adapter is a cross-check, not a replacement status source.

### 3. Status transport parity gate

The official MCP output currently omits total observations, exact source
recording-rule selectors, and a contract-equivalent sample-freshness field.
Therefore MCP-only data cannot yet produce a contract-complete `healthy` status
with feature parity. Promote MCP to an alternative `status` transport only
after one of these conditions is met:

- the upstream MCP surface exposes the missing evidence, or
- a versioned engine contract explicitly models the missing fields and marks
  MCP-only reports incomplete or `unverifiable` without weakening the direct
  reader.

Before promotion, compare direct Prometheus and MCP results for the same
reviewed SLO and fail on objective, period, budget, burn, or identity drift.

## Security And Refusal Rules

- Do not store MCP endpoints, Prometheus credentials, headers, or raw tool
  responses in manifests, evidence artifacts, release bundles, or reports.
- Require HTTP(S), reject URL userinfo/query/fragment, and apply an explicit
  endpoint/egress allowlist for Agent CLI or engine MCP use.
- Sloth's application listener exposes no MCP-specific authentication setting
  in the checked revision. Bind it to loopback or place it behind an approved
  authenticated TLS proxy before remote use.
- Treat tool annotations as metadata, not authorization. Enforce the local
  read-only tool allowlist and never invoke unknown tools.
- Bound cursor traversal, time ranges, response bytes, series points, and
  deadlines. Reject malformed compressed series rather than guessing.
- Sanitize provider-controlled free text before Agent CLI or engine MCP output.
- Any tool inventory, result-schema, version, identity, or reviewed-evidence
  mismatch fails before status normalization.

## Verification Required

The adapter checkpoint needs fake Streamable HTTP MCP tests for initialization,
tool discovery, pagination, exact `sloth_id` reconciliation, version gating,
malformed results, duplicate identities, unknown tools, timeouts, bounded
responses, endpoint redaction, and zero mutation. A controlled integration test
against an official released Sloth binary should follow once a release includes
the MCP server.
