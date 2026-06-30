# Telemetry-First Walkthrough

This walkthrough uses only public-safe representative fixtures and does not require live backend access.

It demonstrates the saved-artifact path from discovery evidence to reviewed handoff, reviewed draft generation, provider manifest review, artifact indexing, and the final live-mutation safety gate.

## Fixture Layout

The stable fixture lives under `examples/onboarding/telemetry-first`:

- `discovery/index.json` is the aggregate batch discovery index.
- `discovery/checkout-prod.json` is the saved normalized discovery result for one scope.
- `reviewed-definition.rb` represents the maintainer-reviewed definition after provider query binding.

The reviewed definition is intentionally separate from the generated draft. `draft-from-handoff` produces a reviewable neutral draft, then a maintainer still binds provider queries before provider generation.

## Commands

Use a temporary workspace for generated artifacts:

```bash
tmpdir="$(mktemp -d)"
fixture="./examples/onboarding/telemetry-first"
handoff_dir="$tmpdir/handoff"
draft_dir="$tmpdir/drafts"
generated_dir="$tmpdir/generated"
mkdir -p "$draft_dir"
```

Build the review queue and saved handoff packet:

```bash
bin/rules-ctl onboarding-summary \
  --handoff-dir "$handoff_dir" \
  "$fixture/discovery/index.json"
```

Record the maintainer review decision:

```bash
bin/rules-ctl review-handoff \
  --accept=request-latency \
  --reject=request-traffic \
  --note='Latency accepted for the walkthrough.' \
  "$handoff_dir/checkout-prod.handoff.json"
```

Validate the accepted handoff:

```bash
bin/rules-ctl validate-handoff "$handoff_dir/checkout-prod.handoff.json"
```

Generate and validate the neutral reviewed draft:

```bash
bin/rules-ctl draft-from-handoff \
  --service=checkout-api \
  --owner=payments-platform \
  "$handoff_dir/checkout-prod.handoff.json" \
  > "$draft_dir/checkout-prod.rb"

bin/rules-ctl validate "$draft_dir/checkout-prod.rb"
```

Generate provider artifacts from the provider-bound reviewed definition:

```bash
bin/rules-ctl generate \
  --provider=datadog \
  --output-dir "$generated_dir" \
  --handoff-dir "$handoff_dir" \
  "$fixture/reviewed-definition.rb"
```

Validate the saved manifest-review report is fresh:

```bash
bin/rules-ctl manifest-review \
  --provider=datadog \
  --manifest "$generated_dir/checkout-api/datadog/manifest.json" \
  --handoff-dir "$handoff_dir" \
  --report "$generated_dir/manifest-review/datadog.json"
```

Write a compact index for the complete handoff bundle:

```bash
bin/rules-ctl onboarding-artifact-index \
  --handoff-dir "$handoff_dir" \
  --draft-dir "$draft_dir" \
  --manifest-dir "$generated_dir" \
  --provider=datadog \
  --output "$tmpdir/artifact-index.json" \
  "$fixture/discovery/index.json"
```

The artifact index includes the saved manifest-review report's `valid` and `fresh` status, stale finding codes when the report no longer matches the current manifest or handoff packet, and the next refresh command for stale reports.

Finally, prove the reviewed artifact gates run before live backend mutation. Without Datadog credentials, the command should stop at `missing_credentials` after review and freshness gates pass:

```bash
DD_API_KEY= DD_APP_KEY= bin/rules-ctl apply \
  --provider=datadog \
  --confirm \
  --manifest "$generated_dir/checkout-api/datadog/manifest.json" \
  --handoff-dir "$handoff_dir" \
  --review-report "$generated_dir/manifest-review/datadog.json"
```

The automated smoke test for this walkthrough is `ruby -Ilib test/telemetry_first_walkthrough_test.rb`.
