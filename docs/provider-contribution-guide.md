# Provider Contribution Guide

This guide defines the boundary for adding or extending providers.

## What A Provider Is

A provider is a deterministic adapter from the neutral reliability model to backend-specific artifacts. It translates validated service definitions into manifests, queries, monitors, dashboards, route mappings, or export files for one observability or incident-management backend.

A provider may:

- map neutral metric bindings to backend query syntax;
- render miss-policy, measurement caveats, notification routes, and dashboard variables;
- declare its automation mode and supported state actions;
- provide dry-run apply plans;
- declare unsupported fields explicitly;
- emit warnings when backend capabilities cannot represent the neutral model;
- add backend-specific metadata needed to make generated artifacts useful and reviewable.

## What A Provider Is Not

A provider is not the source of reliability policy. It must not choose objectives, redefine calculation basis, invent service ownership, decide page policy, import private service definitions, store credentials, or apply changes to live systems as part of normal generation.

Provider generation must not require network access. Live apply flows require a separate explicit command, dry-run output, confirmation flow, injectable clients, and dedicated tests.

## Guardrails

- Consume the neutral model; do not bypass DSL validation.
- Use `bin/rules-ctl model-report` as the review point before provider generation.
- Keep output deterministic for identical inputs.
- Use synthetic fixtures only.
- Do not include secrets, internal hostnames, private service names, private routing targets, or private metric selectors.
- Treat unsupported backend features as explicit warnings, not silent drops.
- Preserve reliability intent fields even when the backend only accepts them as annotations.
- Keep backend-specific dependencies isolated to the provider layer.
- Add tests for generated output shape and unsafe-term scanning.
- Document every new provider option and its default behavior.
- Document the provider automation mode: `live_api`, `manifest_bundle`, `external_generator`, or `manifest_only`.
- Document state actions: `plan`, `apply`, `diff`, `import_existing`, and `prune`.
- Keep live mutation unavailable unless credentials and explicit confirmation are present.

## Contribution Checklist

- Provider contract updated.
- Provider automation mode documented.
- State actions documented.
- Synthetic fixture added or reused.
- Model report reviewed before provider generation.
- Unit tests cover supported output.
- Apply-plan tests cover dry-run behavior.
- Unsupported fields produce warnings.
- `ruby -Ilib test/all_test.rb` passes.
- `scripts/verify.sh` passes.
