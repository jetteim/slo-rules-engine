# Agent Interface Roadmap

**Parent:** public-safe reliability workflow and provider-state roadmap

**Source:** [You Need to Rewrite Your CLI for AI Agents](https://justin.poehnelt.com/posts/rewrite-your-cli-for-ai-agents/), Justin Poehnelt, March 4, 2026

**Decision:** evolve `rules-ctl` into two feature-parity CLI sub-interfaces backed by one command contract: the existing Human CLI with convenience arguments and a new Agent CLI with strict structured requests. Project the same contract into MCP only after the registry and safety boundary are proven.

**Outcome:** an AI agent can discover, validate, invoke, bound, and safely interpret every supported rules-engine workflow without shell guesswork, stale prompt documentation, unbounded output, or a path around reviewed reliability intent.

**Delivery status:** AICLI-F1, AICLI-F2 introspection, and three executable
AICLI-F2 vertical slices are implemented. The Human CLI dispatches through a
validated 40-command registry; a separate versioned command catalog pairs every
Human example with its Agent JSON request; and bounded offline `agent catalog`
plus exact `agent describe` expose strict resolved request schemas and safety
metadata. Strict JSON/file/stdin invocation with versioned envelopes is enabled
for nine commands, including workspace-confined validation/report reads,
file-backed state diff, and confined provider generation/manifest review.
AICLI-F3 read-path/control/size hardening, generated-output containment,
zero-I/O `validate_only` for the first local-write family, and handler output
quarantine are implemented. Remaining command invocation, URL/identifier
hardening, validation-only gates for other write families, agent skill,
response sanitizer, and MCP adapter remain planned.

## Article Summary And Intent

The article distinguishes Human DX from Agent DX. Human interfaces optimize for convenience, discoverability, and recoverable mistakes. Agent interfaces must optimize for deterministic contracts, runtime discoverability, bounded context use, and defense against fast, confident, machine-generated mistakes.

Its central intent is not to discard human-friendly commands. It is to keep them while adding an agent-native route through the same binary and source of truth:

1. Accept full structured request bodies alongside convenience flags.
2. Let callers inspect current input, output, authorization, and side-effect schemas at runtime.
3. Bound large responses with field selection and streamable pagination.
4. Treat agent input as untrusted and validate paths, identifiers, encoding, and control characters.
5. Ship skills or context files that state invariants agents cannot infer.
6. Generate CLI, MCP, extension, and headless surfaces from one contract.
7. Validate locally before mutation and sanitize untrusted provider responses before returning them to an agent.

The engineering conclusion is that predictable machine behavior and defense in depth are product capabilities, not documentation polish.

## Product Adaptation

This engine is not a generic provider API proxy. Reliability intent belongs to the neutral model; providers translate reviewed intent; mutation requires current review evidence, approved plans where supported, confirmation, and durable journals.

Therefore the article's raw-payload guidance is adapted as follows:

- The Agent CLI accepts the complete versioned rules-engine command request, without a lossy layer of bespoke agent flags.
- It does not accept arbitrary Datadog, Prometheus, Sloth, dashboard, monitor, or SLO mutation payloads that bypass the neutral DSL, reviewed provenance, provider validation, exact-plan, or ownership gates.
- Provider-shaped payloads remain evidence inside existing validated manifests and provider-state contracts.
- Human CLI arguments and Agent CLI request objects normalize into the same command handler and produce semantically equivalent domain results.

## Current Baseline And Gaps

| Article capability | Current baseline | Roadmap gap and decision |
| --- | --- | --- |
| Raw Structured Requests Alongside Convenience Flags | Strict inline JSON, workspace-file, and stdin requests now reach typed application commands for three zero-I/O tasks, validation/migration/model reporting, file-backed state diff, and confined generation/manifest review. | Expand one safe command family at a time while retaining existing Human CLI syntax; keep Datadog reads and writes gated until their safety class is ready. |
| Runtime Schema Introspection | A validated registry/catalog covers all 40 commands. Bounded offline `agent catalog` and exact `agent describe` expose strict resolved request schemas, contract references, side effects, I/O, credentials categories, safety gates, and output/MCP metadata. | Keep introspection generated from the registry while invocation, result envelopes, projections, and later MCP are added. |
| Context Window Discipline | Most stdout is JSON, but callers cannot project fields, bound collections consistently, or stream NDJSON pages. | Add schema-checked field masks, explicit limits/cursors, and NDJSON collection streaming. |
| Input Hardening | Enabled Agent read commands share workspace confinement, canonical/symlink checks, traversal/control/pre-encoding rejection, extensions, file/count/byte bounds, deterministic path errors, and adversarial cases. Generation/review output roots, files, derived child paths, and existing symlink ancestors are confined too. | Extend the policy to IDs, URLs/hosts, query/fragment syntax, credential-like keys, and broader generated fuzz coverage before exposing commands that use them. |
| Agent Skills | Repository instructions exist for contributors, not a distributable end-user agent skill. | Ship a versioned `SKILL.md` plus compact context guidance generated or checked against the command registry. |
| Multiple Surfaces From One Contract | Human dispatch, Agent introspection, and nine Agent invocations resolve through one registry and typed application seam; a rules-engine MCP server remains absent. A separate bounded client consumes Sloth's provider-runtime HTTP MCP only for exact reviewed comparison evidence. | Extend the same registry/application seam into remaining Agent invocation, skills metadata, and a later rules-engine MCP stdio adapter. Keep the Sloth MCP comparison behind shared evidence, schema, identity, and no-status-promotion gates. |
| Validation-Only Safety And Response Sanitization | Generation and manifest review now expose distinct zero-I/O `validate_only`; mutation planning, confirmation, review gates, journals, and sanitized backend errors also exist. Other write families and some current dry-run planning may read state, and there is no prompt-injection-aware response policy. | Extend the proven validation-only contract to each remaining write family, preserve observational planning separately, and sanitize or quarantine untrusted free text before Agent CLI/MCP output. |

## Target Architecture

```text
Human CLI adapter        Agent CLI adapter        MCP stdio adapter
(flags/positionals)      (strict JSON request)    (typed tools)
        \                     |                     /
         +------------ single command registry ---+
                              |
                 schema + input safety policy
                              |
                  shared command handlers
                              |
           result envelope + projection + sanitizer
                              |
                 JSON / NDJSON / saved artifacts
```

The single command registry owns:

- stable command ID and version
- Human CLI argument mapping
- Agent CLI request JSON Schema
- result and error schema references
- side-effect class: `none`, `local_read`, `local_write`, `provider_read`, or `provider_mutation`
- `validate_only`, planning, confirmation, review, approval, journal, and freshness requirements
- provider read/write behavior and required environment variables or scopes
- field-mask, collection-limit, cursor, NDJSON, and sanitizer policy
- MCP eligibility and tool metadata
- examples and skill guidance references

The separate `slo-rules-engine/cli-command-catalog/v1` entity is the compact
parity view. Every entry contains `id`, `human_cli`, and `agent_cli_json`. The
Human form is executable now. Every Agent JSON form has a strict runtime-
introspectable request schema. Catalog entries expose
`structured_invocation`; it is true for `providers.list`, `integrations.list`,
`recommend-calculation-basis`, `validate`, `migration-report`, `model-report`,
file-backed `diff`, `generate`, and `manifest-review`, whose Human and Agent
adapters share typed application commands.

Adapters only parse or render. They do not reimplement review policy, provider translation, state planning, or mutation logic.

Sloth's official Streamable HTTP MCP endpoint is a different boundary from the
planned `rules-ctl` MCP stdio server. It is an optional provider runtime, not a
command interface for this engine. The implemented `sloth-mcp compare` Human
command and planned Agent JSON mapping select it through the shared registry and
preserve exact downstream-evidence, version, tool allowlist, identity,
freshness, bounded-output, and no-status-promotion checks. Any future `status`
transport must additionally prove neutral output parity. See
[Official Sloth MCP Comparison](sloth-mcp-integration.md).

## Capability Map

| Capability | Type | Benefit hypothesis | Measures |
| --- | --- | --- | --- |
| Shared command contract and parity | Enabler | One registry prevents semantic drift between interfaces. | 100% of current commands registered; zero parity exceptions at release. |
| Structured agent invocation and introspection | Platform | Agents can discover and invoke current contracts without prompt-baked documentation. | Every command has offline schema; malformed requests fail before handlers. |
| Agent-input and mutation safety | Operational | Field-specific validation and validation-only execution reduce hallucinated reads/writes. | Every mutating command declares side effects and passes zero-I/O validation tests. |
| Context-bounded and sanitized results | Platform | Agents preserve reasoning context and do not ingest unnecessary or unsafe provider text. | Every collection is bounded/projectable; truncation is explicit; sanitizer coverage is tested. |
| Agent knowledge and headless operation | Business | Shipped skills and noninteractive credentials make safe workflows repeatable across agent runtimes. | Skill invariants match registry; no browser-only or payload-carried secret requirement. |
| Typed protocol access | Platform | MCP removes shell escaping while preserving the exact same safety contract. | MCP tool/schema parity is generated and tested for every eligible command. |

## Feature Parity Contract

The two CLI sub-interfaces are:

- **Human CLI:** current commands, convenience flags, positional file arguments, and backward-compatible stdout/exit behavior.
- **Agent CLI:** `rules-ctl agent catalog`, `rules-ctl agent describe <command-id>`, and `rules-ctl agent invoke <command-id> --json=...|--json-file=...`, with strict request/result envelopes and no interactive prompt dependency.

Feature parity means both sub-interfaces reach the same command handler with equivalent normalized inputs and enforce identical provider support, review evidence, freshness, exact-plan, confirmation, journal, credential, mutation, and refusal rules. Syntax and presentation may differ; reliability semantics and side effects may not.

No CLI feature is complete when only one sub-interface exposes it. A command may be intentionally unavailable from both interfaces until its safety contract exists, but it may not silently exist in only one. Once MCP ships, its eligible tool inventory must also be generated from this registry and parity-tested.

The implemented command catalog makes that comparison explicit without mixing
interface syntax into domain handlers:

```json
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
```

### Current Command Inventory To Preserve

| Human CLI command group | Registry coverage required | Agent CLI target | MCP target after AICLI-F6 |
| --- | --- | --- | --- |
| `validate` | Yes | Implemented workspace-confined structured invocation | Yes |
| `validate-handoff` | Yes | Full parity | Yes |
| `generate` | Yes | Implemented confined local-write parity plus zero-I/O `validate_only` | Yes |
| `manifest-review` | Yes | Implemented confined local-write parity plus zero-I/O `validate_only` | Yes |
| `apply` | Yes | Validate, plan, and confirmed execution remain distinct | Yes, mutation metadata mandatory |
| `diff` | Yes | Implemented for local Prometheus Stack/Sloth managed-state reads; Datadog Agent reads remain gated | Yes |
| `import` | Yes | Full parity | Yes |
| `prune` | Yes | Validate, plan, and confirmed execution remain distinct | Yes, mutation metadata mandatory |
| `status` | Yes | Manifest, bundle, and portfolio forms | Yes |
| `sloth-evidence capture/status` | Yes | Full parity with local-only side effects and reviewer/freshness gates | Yes |
| `sloth-mcp compare` | Yes | Read-only exact-evidence comparison with bounded runtime and no status promotion | Yes |
| `agent catalog/describe` | Yes | Implemented offline introspection; invocation mapping remains registry-backed | Yes |
| `bundle create/plan/apply/verify/status` | Yes | Full lifecycle parity | Yes |
| `journal create/status` | Yes | Full parity | Yes |
| `plan approve/status/apply/resume` | Yes | Full parity with review and confirmation | Yes |
| `lookup-telemetry` | Yes | Full parity with bounded output | Yes |
| `discover-telemetry` | Yes | Single and batch parity with NDJSON option | Yes |
| `providers list` | Yes | Implemented structured invocation with zero I/O | Yes |
| `integrations list` | Yes | Implemented structured invocation with zero I/O | Yes |
| `generate-routes` | Yes | Full parity | Yes |
| `candidates` | Yes | Full parity with field masks | Yes |
| `draft-definition` | Yes | Full parity | Yes |
| `draft-from-handoff` | Yes | Full parity | Yes |
| `onboarding-summary` | Yes | Full parity with bounded scopes | Yes |
| `onboarding-artifact-index` | Yes | Full parity | Yes |
| `review-handoff` | Yes | Explicit local-write classification | Yes |
| `recommend-calculation-basis` | Yes | Implemented structured invocation with zero I/O | Yes |
| `reality-check` | Yes | Full parity | Yes |
| `migration-report` | Yes | Implemented workspace-confined structured invocation with finding exit parity | Yes |
| `model-report` | Yes | Implemented workspace-confined structured invocation | Yes |

## Functional Requirements

- **AICLI-FR-001:** The binary shall expose a Human CLI and Agent CLI as separate sub-interfaces over the same handlers.
- **AICLI-FR-002:** A single command registry shall be the canonical inventory for command IDs, schemas, side effects, safety gates, examples, and adapter mappings.
- **AICLI-FR-003:** The registry shall cover every command group in the current parity inventory before the Agent CLI is declared generally available.
- **AICLI-FR-004:** Human CLI convenience arguments and Agent CLI request objects shall normalize to the same typed command request.
- **AICLI-FR-005:** Agent invocation shall accept exactly one complete request through inline JSON, a JSON file, or stdin, with explicit precedence and mutual exclusion; output format shall be selected deterministically by explicit argument, then a documented headless environment variable, then the Agent CLI JSON default, never by TTY inference.
- **AICLI-FR-006:** Agent request schemas shall be strict JSON Schema with `additionalProperties: false` by default, explicit required fields, enums, formats, bounds, and schema versions.
- **AICLI-FR-007:** `agent catalog` and `agent describe` shall return command, request, result, error, side-effect, auth/scope, provider-read/write, and safety metadata without file writes, backend calls, or credentials.
- **AICLI-FR-008:** Agent success shall use a versioned envelope containing request ID, command ID/version, outcome, side-effect evidence, result, findings, artifact references, truncation state, and schema version; `--format=json|ndjson` and `RULES_CTL_OUTPUT_FORMAT` shall not conflict with existing `--output=FILE` persistence.
- **AICLI-FR-009:** Agent usage, validation, policy, backend, and execution failures shall use a versioned JSON error envelope on stdout with stable codes and nonzero exit status; stderr shall be reserved for transport diagnostics that contain no result data.
- **AICLI-FR-010:** Runtime schema output shall resolve local references deterministically and expose no secret values, runtime endpoints, or environment contents.
- **AICLI-FR-011:** Result schemas shall declare supported field masks; invalid or unknown projections shall fail before handler execution.
- **AICLI-FR-012:** Collection results shall support explicit limits and cursors, and eligible commands shall support NDJSON page or item streaming without buffering an unbounded top-level array.
- **AICLI-FR-013:** Truncated results shall report `truncated`, returned count, applied limit, and a deterministic continuation cursor or an explicit reason that continuation is unavailable.
- **AICLI-FR-014:** Agent-facing output path fields shall canonicalize against an explicit workspace root, reject path traversal and symlink escape, and distinguish read paths from create/write destinations.
- **AICLI-FR-015:** Field-specific string validation shall reject prohibited control characters, embedded query or fragment syntax in resource identifiers, pre-encoded identifiers that risk double encoding, invalid URL userinfo, and unsupported schemes; validated URL path segments shall be encoded exactly once at the transport boundary.
- **AICLI-FR-016:** Agent requests shall enforce declared byte, nesting-depth, collection-size, and string-length limits before command handlers or provider clients are constructed.
- **AICLI-FR-017:** Credentials shall be accepted only through declared headless credentials environment variables, approved credential-file references, or noninteractive service/workload identity where a provider supports it; browser redirects shall not be required, and request bodies, schemas, results, logs, skills, and MCP metadata shall never contain secret values.
- **AICLI-FR-018:** Every command shall declare its local/provider reads and writes before invocation, and the result shall report the side-effect class actually exercised.
- **AICLI-FR-019:** Every command capable of a write shall support `validate_only`, which performs schema, policy, review-reference, and local contract validation with zero file writes, zero provider calls, and zero credential loading.
- **AICLI-FR-020:** Observational planning that reads managed or backend state shall remain distinct from `validate_only` and shall declare those reads before execution.
- **AICLI-FR-021:** Provider mutation shall preserve all current reviewed provenance, freshness, ownership, approved-plan, exact-plan, confirmation, scope-lock, journal, and verification gates in both CLI sub-interfaces and MCP.
- **AICLI-FR-022:** Agent CLI and MCP output shall pass untrusted free-text fields through a declared response sanitization policy; prompt-injection-bearing or policy-rejected content shall be redacted or quarantined with fingerprints and findings rather than emitted inline.
- **AICLI-FR-023:** The project shall ship a versioned `SKILL.md` with valid frontmatter and binary prerequisites plus compact `CONTEXT.md` guidance covering discovery, field masks, bounded reads, validation-only behavior, confirmation, reviewed evidence, credential rules, and refusal handling.
- **AICLI-FR-024:** An MCP stdio server shall generate typed tools from the same registry, support an explicit command/provider allowlist, and invoke the same handlers without shell construction.
- **AICLI-FR-025:** Existing Human CLI command syntax, stdout payloads, exit codes, persisted schemas, review gates, and provider behavior shall remain backward compatible unless a separately documented deprecation is approved.
- **AICLI-FR-026:** Every CLI change shall update Human CLI mapping, Agent CLI mapping, registry schema/metadata, equivalence tests, runtime introspection, skills guidance when affected, MCP projection when available, README, and engineering use cases in the same checkpoint.

## Non-Functional Requirements

- **AICLI-NFR-001 Determinism:** identical normalized requests and controlled evidence shall produce canonical JSON with stable ordering and equivalent Human/Agent domain results.
- **AICLI-NFR-002 Security:** request processing shall assume agent input is untrusted; validation and authorization occur before side effects or provider-client construction.
- **AICLI-NFR-003 Secret safety:** credentials, raw authorization headers, raw backend bodies, and environment values shall not appear in output, schema, logs, errors, saved artifacts, skills, or MCP descriptors.
- **AICLI-NFR-004 Context budget:** every collection command shall declare tested default and maximum result budgets; exceeding them produces explicit truncation or NDJSON continuation rather than silent omission or unbounded output.
- **AICLI-NFR-005 Streaming:** NDJSON execution shall use memory proportional to one declared page or item batch, not the total result set.
- **AICLI-NFR-006 Offline discovery:** registry catalog/schema/skill generation shall require no backend, credentials, source artifact mutation, or network access.
- **AICLI-NFR-007 Backward compatibility:** the existing Human CLI remains characterized by current tests throughout migration; Agent CLI work shall not rewrite domain behavior.
- **AICLI-NFR-008 Maintainability:** command behavior, schema, side-effect metadata, CLI mappings, and MCP metadata shall not be independently duplicated outside the registry.
- **AICLI-NFR-009 Auditability:** agent mutation results shall retain command/request identity, approval/review references, journal/result references, and sanitized side-effect evidence without secret material.
- **AICLI-NFR-010 Portability:** the baseline Agent CLI, schema introspection, skill, and local sanitizer shall work without a vendor-specific agent runtime or hosted sanitization service.
- **AICLI-NFR-011 Testability:** schema golden tests, Human/Agent equivalence tests, no-I/O validation tests, fuzz/property tests, context-limit tests, sanitizer fixtures, and MCP contract tests shall run with public-safe fixtures.
- **AICLI-NFR-012 Failure isolation:** malformed requests, invalid projections, unsafe paths/IDs, sanitizer failures, and parity gaps shall fail closed before unrelated targets or operations begin.

## Feature Packets

### AICLI-F1: Shared Command Registry And Parity Baseline

**AICLI-F1 status:** implemented.

**Value:** establishes one inventory and makes interface drift measurable before adding another adapter.

**Acceptance criteria:** every current command has an ID, versions, Human CLI mapping, request/result/error schema references, side effects, safety gates, provider I/O, output controls, and parity test; missing metadata blocks registry validation.

**Evidence:** `CommandRegistry` validates completeness, uniqueness, immutability,
root-adapter consistency, and required metadata for 40 commands. Human top-level
and grouped-subcommand dispatch resolve through it. `CommandCatalog` is a
separate versioned entity pairing current Human commands with planned Agent JSON
requests. Existing CLI characterization remains unchanged. Strict request
schemas are resolved for every command; executable expansion remains AICLI-F2
scope.

**Architecture impact:** new command-contract component between adapters and existing handlers; no provider or neutral-model dependency reversal.

### AICLI-F2: Structured Agent CLI And Runtime Introspection

**AICLI-F2 status:** partially implemented. Offline bounded catalog, exact
describe, strict resolved request schemas for all 40 commands, and JSON-only
introspection errors are complete. Strict inline JSON, workspace-file, and
stdin request sources, explicit/environment/default format precedence,
deterministic request IDs, and versioned result/error envelopes are implemented
for `providers.list`, `integrations.list`, `recommend-calculation-basis`,
`validate`, `migration-report`, `model-report`, and `diff`. Their Human and
Agent adapters share typed application commands that do not print or exit.
`diff` is intentionally Agent-enabled only for Prometheus Stack/Sloth local
managed-file reads; Datadog state reads and all write-capable commands remain
gated.

**Value:** agents can discover and invoke complete current contracts through JSON instead of reconstructing shell syntax.

**Acceptance criteria:** offline catalog/describe and strict raw JSON/file/stdin invocation work for an initial vertical slice, then every registered command; Human and Agent normalized requests/results are equivalent; JSON errors never degrade to prose usage output.

**Architecture impact:** Agent CLI adapter, request/result envelopes, schema resolver, `--format=json|ndjson` terminology that does not conflict with existing `--output=FILE` persistence.

**Current evidence:** inline, file, and subprocess-stdin requests produce the
same results and exit classes as their Human commands. Unknown fields, mismatched command
identity/version, malformed JSON, ambiguous sources, out-of-workspace request
files, unknown commands, unsupported formats, and gated commands return one
`slo-rules-engine/agent-command-error/v1` value with no result data on stderr.
The result path returns `slo-rules-engine/agent-command-result/v1` with explicit
exit status, declared/exercised side effects, retained findings, and explicit
non-truncation state. Application stdout/stderr and direct exits are quarantined
instead of contaminating machine output.

### AICLI-F3: Adversarial Input And Validation-Only Boundary

**AICLI-F3 status:** partially implemented. The nine executable commands
reject control characters before dispatch. Agent file inputs are
workspace-confined and bounded, reject absolute/traversal/pre-encoded paths,
enforce expected extensions, canonicalize symlinks, and reject escape or
oversized input before content reads. File-backed diff validates every input
path before parsing its manifest and performs no provider network call or
write. Generation/review validate every input and destination lexically before
content reads; normal execution confines output roots/files and derived
service/provider children after symlink resolution; `validate_only` returns
explicit zero-I/O evidence without opening missing sources or creating output
parents. IDs, URLs/hosts, credential-like keys, broader generated fuzzing, and
zero-I/O `validate_only` for the remaining write commands remain open.

**Value:** machine-generated mistakes fail before file access, credentials, backend reads, or writes.

**Acceptance criteria:** shared validators cover path traversal, symlink escape, control characters, unsafe resource IDs, embedded query/fragment text, pre-encoded values, URL policy, and size/depth limits; every write-capable command passes a zero-I/O `validate_only` test; generated/fuzzed invalid requests fail with stable codes.

**Architecture impact:** input safety policy and filesystem/URL/identifier value types shared by both adapters and MCP.

### AICLI-F4: Context-Bounded And Sanitized Output

**Value:** agents receive only the evidence needed for the current decision and do not ingest unsafe provider-controlled text by default.

**Acceptance criteria:** schema-checked field masks, declared limits/cursors, NDJSON streaming, explicit truncation, and response sanitization work for telemetry, onboarding, manifest/release, provider-state, and live-status collections; sanitizer failure is fail-closed.

**Architecture impact:** result projection/streaming and sanitizer components after handlers, before every agent-facing adapter.

### AICLI-F5: Versioned Agent Skill And Context Guidance

**Value:** agent runtimes receive compact operational invariants that stay aligned with executable contracts.

**Acceptance criteria:** shipped `SKILL.md` and `CONTEXT.md` guidance cover catalog-first invocation, field masks, validation-only, planning versus mutation, confirmation, reviewed evidence, output limits, credentials, and common refusal recovery; frontmatter declares the version and binary dependency; registry/skill drift tests fail CI.

**Architecture impact:** distributable knowledge artifact with generated/checkable command references; no runtime policy in prose only.

### AICLI-F6: MCP Stdio And Headless Runtime

**Value:** agents can call typed tools without shell escaping while keeping the same authorization and mutation boundaries.

**Acceptance criteria:** MCP tools are generated from registry schemas, use allowlists, return the Agent CLI envelopes, load credentials only through declared headless paths, preserve side-effect metadata, and pass command parity tests without executing a shell. Provider-runtime MCP adapters, including Sloth's upstream HTTP MCP surface, remain behind shared handlers and cannot introduce MCP-only inputs, outputs, safety gaps, or provider-payload bypasses.

**Architecture impact:** optional stdio protocol adapter over registry and handlers; no independent MCP business logic.

### AICLI-F7: Full Parity, Compatibility, And Rollout Gate

**Value:** the agent surface can become supported without breaking existing operators or leaving hidden one-interface commands.

**Acceptance criteria:** all inventory rows have Human/Agent equivalence and MCP eligibility evidence; current CLI characterization remains green; schemas and skills are versioned; context and security NFRs pass; no undocumented parity exception remains.

**Architecture impact:** release gate and compatibility policy, not a new runtime component.

## Delivery Order

1. AICLI-F1 delivered the architectural foundation and registered current commands without changing their behavior.
2. Deliver AICLI-F2 first for read-only catalog, validation, reporting, and one state-planning vertical slice; expand only through registry-backed mappings.
3. Complete AICLI-F3 before exposing any Agent CLI local write or provider mutation.
4. Deliver AICLI-F4 for high-volume discovery/status/reporting paths before claiming context-safe operation.
5. Ship AICLI-F5 when the first Agent CLI slice is usable so guidance and behavior evolve together.
6. Add AICLI-F6 only after schemas, safety metadata, and Agent CLI envelopes are stable.
7. Close AICLI-F7 before calling the Agent CLI or MCP generally available.

The initial implementation packet should contain no more than these seven feature packets. Story slicing happens one feature at a time.

## Verification Strategy

| Requirement area | Evidence |
| --- | --- |
| Registry coverage | Test compares the current Human CLI inventory with registered command IDs and adapter mappings. |
| Human/Agent parity | Table-driven equivalence tests compare normalized request, domain result, exit class, provider reads/writes, and refusal codes. |
| Schema introspection | Golden JSON Schema tests plus offline/no-credential/no-client assertions. |
| Input hardening | Generated and fuzz/property cases for traversal, symlinks, controls, `?`, `#`, `%`, encoding, URLs, bounds, and unknown fields. |
| Mutation safety | Spies prove `validate_only` performs no filesystem/provider I/O and all existing review/exact-plan/journal gates remain active. |
| Context control | Field-mask, cursor, limit, truncation, NDJSON ordering, and bounded-memory tests. |
| Sanitization | Public-safe fixtures containing prompt-injection-bearing text, secrets, and unsafe markup; output retains findings/fingerprints, not rejected text. |
| Skills | Registry-to-`SKILL.md` invariant and command-reference checks. |
| MCP | Generated tool inventory/schema parity, allowlist, envelope, auth, and no-shell tests. |
| Compatibility | Existing full suite plus schema/exit/stdout snapshots for the Human CLI. |

## Article Revalidation

After drafting this roadmap, every recommendation in the source article was checked again against capabilities, requirements, features, and verification hooks.

| Source recommendation | Roadmap coverage | Revalidation result |
| --- | --- | --- |
| Raw payload path plus human convenience | AICLI-FR-001 through 006; AICLI-F2 | Covered with full rules-engine request JSON; arbitrary provider mutation bypass is explicitly rejected. |
| Runtime schema introspection | AICLI-FR-007 and 010; AICLI-F1/F2 | Covered offline from one registry. |
| JSON output | AICLI-FR-005/008/009; AICLI-F2 | Gap found and corrected: versioned envelopes now have deterministic argument/environment/default precedence with no TTY inference, while `--format` avoids conflict with current file `--output`. |
| Field masks and streamable pagination | AICLI-FR-011 through 013; AICLI-F4 | Covered with projection, limits, cursors, truncation, and NDJSON. |
| Input hardening | AICLI-FR-014 through 016; AICLI-F3 | Gap found and corrected: paths, symlinks, controls, IDs, query/fragment text, pre-encoding, URLs, resource bounds, and exactly-once path-segment encoding are explicit. |
| Agent skills/context | AICLI-FR-023; AICLI-F5 | Covered with versioned skill and drift tests. |
| MCP and headless credentials | AICLI-FR-017/024; AICLI-F6 | Covered from the registry with allowlists, environment/file references, and noninteractive service/workload identity where supported; browser redirects are excluded. |
| Framework extensions and environment integration | AICLI-FR-005/008/017/023/024; AICLI-F5/F6 | Covered for deterministic output environment configuration, skill packaging, headless auth, and MCP; vendor-specific extension packaging is intentionally deferred. |
| Dry-run before mutation | AICLI-FR-018 through 021; AICLI-F3 | Gap found and corrected: current observational dry-run may read state, so the roadmap adds separate zero-I/O `validate_only` semantics. |
| Response sanitization | AICLI-FR-022; AICLI-F4 | Gap found and corrected: current error redaction is retained, and agent-facing untrusted free text gains a sanitizer/quarantine contract. |
| Keep human ergonomics | AICLI-FR-001/004/025/026; AICLI-F7 | Covered with backward compatibility and mandatory dual-interface updates. |
| Test agent-specific mistakes | AICLI-NFR-011/012; AICLI-F3/F7 | Covered with generated/fuzz inputs and fail-closed isolation. |

No article theme remains orphaned at roadmap level. AICLI-F1, AICLI-F2 runtime
introspection, the zero-I/O slice, the first workspace-read/state-plan slice,
and the first confined local-write slice are implemented. AICLI-F3 is proven
for the enabled read fields and generation/review outputs; remaining structured
invocation and AICLI-F3 through F7 stay open and must progress through the
feature gates above. This revalidation does not claim full Agent CLI parity or
that the rules-engine MCP exists.

## Accepted Deferrals

- A hosted model-armor provider is not selected. A portable sanitizer contract and local baseline come first; hosted policies can be adapters later.
- Gemini-specific extensions are not a core target. The versioned skill and MCP surface are runtime-neutral.
- Automatic browser authentication is excluded. Existing and future provider credentials remain headless, external, least-privilege, and absent from requests/results.
- Agent-driven provider mutation is not enabled until registry, strict schemas, AICLI-F3 safety tests, and all existing review/exact-plan/journal gates are proven together.
