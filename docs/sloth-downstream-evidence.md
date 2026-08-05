# Sloth Downstream Evidence Contract

This contract links a reviewed Sloth provider manifest and its native
`prometheus/v1` inputs to saved Prometheus recording rules produced outside the
engine. It is credential-free, read-only with respect to providers, and does
not execute Sloth or query Prometheus.

The characterized record set follows Sloth's official generated-rule example:
<https://sloth.dev/examples/default/getting-started/>. The engine validates
saved output structurally instead of treating that example as a neutral-model
contract.

## Capture

```bash
bin/rules-ctl sloth-evidence capture \
  --manifest=./work/managed/checkout-api/sloth/manifest.json \
  --input=./work/managed/checkout-api/sloth/generated/sloth.yaml \
  --generated-rules=./work/sloth-output/checkout-api-rules.yaml \
  --reviewer=team/payments-sre \
  --reviewed-at=2026-08-04T12:00:00Z \
  --output=./work/sloth-evidence/checkout-api.json
```

Repeat `--input` in manifest `artifacts.sloth_specs` order when a manifest has
multiple native inputs. The command reads the manifest, every native input,
and the generated-rule YAML. It writes one artifact and prints the identical
JSON to stdout.

The schema is `slo-rules-engine/sloth-downstream-evidence/v1`; the kind is
`SlothDownstreamEvidence`. `evidence_id` is content-addressed from:

- downstream reviewer identity, ISO 8601 timestamp, and attestation
- reviewed manifest provenance
- canonical manifest, native-input, and generated-rule fingerprints
- exact per-SLO generated record names, labels, selectors, and source paths
- provider-specific status bindings

Each reviewed Sloth SLO must map to one non-empty `sloth_id` and exactly one of
these required records:

| Status role | Reviewed generated evidence |
| --- | --- |
| Base error ratio | Shortest-window `slo:sli_error:ratio_rate*` record |
| Evaluation error ratio | `slo:sli_error:ratio_rate*` whose `sloth_window` matches `slo:time_period:days` |
| Objective | `slo:objective:ratio` |
| Allowed error budget | `slo:error_budget:ratio` |
| Current burn | `slo:current_burn_rate:ratio` |
| Evaluation-period burn | `slo:period_burn_rate:ratio` |
| Remaining error budget | `slo:period_error_budget_remaining:ratio` |
| Metadata | `sloth_slo_info` |

Objective and allowed-budget record values must agree with the reviewed native
spec. Generated labels must resolve only to SLOs present in that spec.

Sloth's characterized default output does not create a dedicated observation
record. The evidence artifact therefore preserves the exact reviewed
`sli.events.total_query` as the observation binding. It does not mislabel an
error-ratio record as request volume. Success ratio and freshness queries are
derived only from the captured evaluation error-ratio identity inside this
provider-specific artifact; no PromQL enters the neutral DSL. Current and
evaluation-period burn bindings carry a provider status threshold of `1.0`,
meaning the error budget is being consumed faster than its sustainable rate;
this does not replace Sloth's generated alert-window thresholds.

## Freshness Status

```bash
bin/rules-ctl sloth-evidence status \
  ./work/sloth-evidence/checkout-api.json
```

The command first validates schema, credential safety, and content identity.
Only then does it reread the source paths recorded in the artifact. Stdout is
one `slo-rules-engine/sloth-downstream-evidence-status/v1`
`SlothDownstreamEvidenceStatus` with:

- `status: fresh|stale` and `fresh: true|false`
- one expected/actual fingerprint check per manifest, native input, and
  generated-rule source
- stable findings for stale or unavailable sources

Fresh status exits zero. Stale status prints the complete status artifact and
exits one. Content-identity or schema failure prints
`invalid_sloth_downstream_evidence` and exits one without trusting or reading
the recorded source paths.

## Refusal Contract

Capture writes nothing when any input is invalid. Stable finding codes include:

- `missing_review_provenance`
- `native_input_manifest_mismatch` and `sloth_native_input_count_mismatch`
- `missing_generated_recording_rule`, `ambiguous_generated_recording_rule`,
  and `unrelated_generated_recording_rule`
- `ambiguous_sloth_generated_identity`
- `sloth_objective_mismatch` and `sloth_error_budget_mismatch`
- `credential_like_key`

Status uses `sloth_evidence_identity_mismatch`, `stale_sloth_manifest`,
`stale_sloth_native_input`, and `stale_generated_rules`. Unsafe YAML aliases,
malformed JSON/YAML, missing files, and unreadable files fail closed with
source-specific findings. A rehashed artifact whose identity, selectors, or
status bindings are not derived exactly from the linked current sources fails
`sloth_evidence_source_derivation_mismatch`.

## Safety Boundary

Both commands perform local file reads only, except that capture writes the
explicit `--output` artifact after every validation passes. They load no
credentials, make no provider call, execute no shell command, do not run
Sloth, and do not apply or reload Prometheus rules.

Direct `status --provider=sloth` now consumes this artifact. It revalidates the
content ID and every source fingerprint, requires an exact manifest/service/SLO
coverage match, then queries only the saved bindings through an explicit
Prometheus runtime. Release-bundle downstream verification remains unsupported
until bundles package current evidence per target.

Sloth's own main branch also contains a read-only HTTP MCP server. Its planned
role, current status-parity gaps, setup, and promotion gates are documented in
[Official Sloth MCP Integration Path](sloth-mcp-integration.md).
