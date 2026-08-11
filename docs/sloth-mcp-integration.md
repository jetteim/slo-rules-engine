# Official Sloth MCP Comparison

Use this workflow to compare one reviewed Sloth manifest and its current
downstream evidence with the operating view exposed by Sloth's official MCP
server. The result is supplemental provider evidence. It does not replace the
engine's evidence-backed Prometheus status reader and cannot authorize a write.

## Verified Upstream Boundary

The official [`slok/sloth`](https://github.com/slok/sloth) repository was
rechecked at main revision
[`8a3be4fab79defa4448d09d91b48422615980b05`](https://github.com/slok/sloth/commit/8a3be4fab79defa4448d09d91b48422615980b05)
on 2026-08-10. That revision exposes a stateless Streamable HTTP MCP handler
using protocol `2025-11-25` and six read-only tools:

| Tool | Comparison use |
| --- | --- |
| `context` | Proves the running Sloth version before domain reads |
| `list_services` | Reconciles exact service identity and reviewed SLO count |
| `list_slos` | Reconciles exact `sloth_id`, objective, period, burn, budget, and alert state |
| `get_slo` | Detects list/detail disagreement for the matched provider ID |
| `get_slo_burned_budget_range` | Captures bounded current/expected remaining-budget series |
| `get_slo_sli_availability_range` | Captures bounded availability series for the requested interval |

The latest tagged release observed was still `v0.16.0`, which predates the MCP
surface. The implemented capability matrix therefore accepts only the exact
tested main-branch runtime version `dev`. A tagged version must be separately
characterized and added before the engine accepts it.

## Run The Comparison

Start a Sloth main-branch build on a loopback or protected application listener:

```bash
sloth server \
  --mcp-enabled \
  --mcp-path=/mcp \
  --app-listen-address=127.0.0.1:8080 \
  --prometheus-address=http://localhost:9090
```

Then compare its operating view with the exact reviewed artifacts:

```bash
bin/rules-ctl sloth-mcp compare \
  --manifest=./managed/checkout-api/sloth/manifest.json \
  --evidence=./work/sloth-evidence/checkout-api.json \
  --endpoint=http://127.0.0.1:8080/mcp \
  --allow-host=127.0.0.1 \
  --expected-version=dev \
  --from=2026-08-01T00:00:00Z \
  --to=2026-08-05T00:00:00Z \
  --output=./work/sloth-mcp/checkout-api.json
```

`--allow-host` is repeatable. `--endpoint`, `--allow-host`,
`--expected-version`, the time range, and `--output` are always explicit; the
command has no environment endpoint fallback. Optional bounded controls are
`--page-size`, `--max-pages`, `--max-series-points`, `--timeout-seconds`, and
`--max-response-bytes`.

## What The Tool Generates

Stdout and `--output` contain identical
`slo-rules-engine/sloth-mcp-comparison/v1` `SlothMcpComparison` JSON:

- content fingerprints for the reviewed manifest and downstream evidence plus
  the exact evidence ID
- protocol, Sloth version/capability, sorted six-tool inventory, and a tool
  schema fingerprint, but never the runtime endpoint
- requested range and every enforced page, series, timeout, and byte bound
- one exact reviewed identity per SLO with reviewed objective/window and
  provider objective/period, burn, consumed budget, alerts, remaining-budget
  series, and availability series
- `matched` or `drift` status with stable findings and deterministic
  `sloth-mcp-comparison-<sha256>` identity
- `authoritative_status_transport: false` so downstream consumers cannot
  mistake the comparison for the neutral five-state status report

`matched` exits zero. Semantic objective, period, list/detail, or budget drift
is still saved, prints `status: drift`, and exits one. Contract, identity,
transport, or evidence failures print a sanitized JSON error envelope, exit
one, and do not write the requested report.

## Fail-Closed Contract

Before constructing the MCP client, the command validates the reviewed Sloth
manifest, evidence content identity, exact manifest/evidence link, complete SLO
coverage, and every recorded source fingerprint. It then:

1. requires an HTTP(S) URL without userinfo, query, or fragment
2. requires the endpoint host in the explicit allowlist
3. initializes exactly MCP protocol `2025-11-25`
4. requires server name `sloth` and the exact tested runtime version
5. requires exactly the six pinned tools, `readOnlyHint: true`, and pinned input
   and output schema shapes before calling a domain tool
6. traverses service and SLO cursors within configured bounds
7. rejects missing, duplicate, grouped, malformed, or unexpected identities
8. calls only the locally allowlisted tool names and accepts structured content
   only
9. bounds response bytes while streaming and bounds compressed series points
10. sanitizes HTTP, JSON-RPC, and tool failures without retaining raw backend
    bodies, provider descriptions, alert names, endpoints, or credentials

The report builder also performs the repository credential-key scan before
persisting output. The command performs provider reads only. It does not invoke
Sloth generation, reload Prometheus, mutate an SLO, or call any unknown tool.

## Status Parity Boundary

The official MCP output does not expose total observations, exact source
recording-rule selectors, or a contract-equivalent sample-freshness field.
Consequently it cannot produce the engine's complete
`slo-rules-engine/live-slo-status/v1` evidence or classify a reviewed SLO as
`healthy`, `at_risk`, `exhausted`, `missing_telemetry`, or `unverifiable` with
feature parity.

Continue to use:

```bash
bin/rules-ctl status \
  --provider=sloth \
  --manifest=./managed/checkout-api/sloth/manifest.json \
  --evidence=./work/sloth-evidence/checkout-api.json \
  --base-url=http://localhost:9090 \
  --output=./work/status/checkout-api-sloth.json
```

MCP may become an alternative status transport only after upstream exposes the
missing evidence and a released version passes contract and direct-versus-MCP
parity tests. Until then, the comparison cannot promote release verification or
replace reviewed downstream evidence.

## Deployment And Verification Notes

The checked Sloth revision has no MCP-specific authentication setting. Keep the
listener on loopback or place it behind an approved authenticated TLS proxy.
Do not embed proxy credentials in the endpoint URL; configure approved
transport authentication outside persisted engine artifacts.

The implementation is covered by fake-client comparison tests, request
transport tests, Human/Agent command-registry parity tests, and command output
tests. A controlled upstream audit on 2026-08-10 instantiated the official
handler and used the official Go MCP SDK client to complete initialization and
`tools/list`; the observed schemas match the pinned engine contract. A full
comparison against a tagged Sloth binary and real Prometheus data remains
blocked until an official release contains MCP.

This upstream provider-runtime MCP endpoint is separate from the planned
`rules-ctl` MCP stdio adapter in AICLI-F6. The latter will project engine
commands from the shared registry and must not reimplement these provider tools.
