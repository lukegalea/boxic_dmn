# Changelog

All notable changes to `boxic_dmn` will be documented in this file.

The project follows Semantic Versioning. While the package is below version
1.0.0, breaking changes increment the minor version.

## Unreleased

Requires Elixir 1.20 or later.

- Fix a temp-file collision in XML schema validation: the temp file name was
  unique only within one VM, so two VMs sharing a temp directory could pick the
  same name and fail the exclusive open. The name now includes the OS pid and
  random bytes.

## 0.4.0

Fork release, based on upstream `koenusz/boxic` `apps/boxic_dmn` (the code
published to Hex as `boxic_dmn 0.3.0`).

- Add `Boxic.DMN.evaluate_with_trace/3,4`: evaluates a decision exactly like
  `evaluate/3,4` and additionally returns
  `%{matched_rules: [rule_id], hit_policy: atom}` — the ids of every
  decision-table rule that matched the inputs (in table order; empty when no
  rule matched and default outputs applied) and the atomized hit policy that
  reduced them (`nil` for non-decision-table expressions). The `evaluate/3,4`
  contract is unchanged; hit-policy violation errors keep their shape.
- Relax the required Elixir version from `~> 1.20.0` to `~> 1.18` so the
  engine can run on the toolchains its consumers use.
- Convert the extracted package to a standalone Mix project (drop the
  monorepo umbrella build paths and the sibling `boxic_feel` override; depend
  on Hex `boxic_feel ~> 0.2.0` directly).

## 0.3.0 - 2026-07-24
- Centralize definitions/local FEEL language inheritance and preserve omitted
  declarations in the normalized model.
- Add capability-specific validation and decision-service evaluator options.
- Isolate trusted external functions from model input, define built-in
  precedence, and redact host failures.
- Publish the conformance contract and construct capability ledger.

## 0.2.0 - 2026-07-19

- Add deterministic DMN 1.4 XML encoding through `Boxic.DMN.encode_xml/2`.
- Add structured serialization preflight errors and explicit rejection of
  version-mismatched or lossy loaded models.
- Retain the source DMN profile, import declarations, and serialization
  fidelity on normalized models.
- Preserve semantically significant FEEL text whitespace during loading.
- Add immutable, ID-based decision-table authoring operations for cells, rules,
  inputs, outputs, ordering, and hit policies.
- Validate focused generated-document fixtures against the vendored official
  DMN 1.4 schema.
- Add generated-model, injection, XML-code-point, bounded-error, atom-safety,
  deep-recursion, and standalone large-table performance coverage.
- Audit all 69 distinct models in the implemented TCK writer profile: all 69
  are explicitly rejected for their newer DMN namespace, with zero writer
  failures or implicit version conversions.

## 0.1.0 - 2026-07-18

- Initial public release.
- Load and normalize DMN 1.4 XML models.
- Validate model structure, types, and references.
- Evaluate decisions, decision tables, boxed expressions, business knowledge
  models, imports, and decision services.
- Validate against DMN TCK revision
  `0dbcaf9b98bc3af4e36d44a7aed95e9e85703a13`.
- Pass all 1,485 cases in the pinned DMN TCK profile.
