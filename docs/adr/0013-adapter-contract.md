# 0013. Adapter contract and the docs-first rule

- Status: Accepted
- Date: 2026-10-06

## Context

Adapters are the only tool-specific code. Their inputs are formats we do not control, and a guessed format becomes a
bug in every user's CI.

## Decision

- An adapter is a pure function: `Result<AdapterOutput, Failure> parse(RawArtifact artifact)`.
  - `RawArtifact`: `source`, `path`, `contents` (String). Read in `io/`.
  - `AdapterOutput`: `findings`, `ruleOutcomes`, `measurements`, `toolVersion`.
- Each adapter lives in `lib/src/adapters/<tool>/` and exports only its `parse` function and its target normalizer
  ([ADR 0007](0007-fingerprints-and-normalization.md)). No tool-specific type leaves the directory.
- **Docs first.** Before an adapter is written, the implementer reads the tool's documentation and real sample
  output, and records fixtures from the real tool under `test/fixtures/<tool>/<tool-version>/`, with a `SOURCE.md`
  giving the tool version, the command that produced each file, and the docs it was checked against. If the format
  is undocumented, the implementer stops and asks the maintainer.
- **Versions.** Each adapter declares the tool major versions it was tested against. Output from an untested major
  version is an `AdapterFailure` naming the version and asking for an issue, not a best-effort parse.
- Each adapter documents its severity and category mapping in a table in its fixture `SOURCE.md`.

Format status as of 2026-10-06. Each row is checked again when its adapter is built.

| Source               | Format documentation                                                    | Phase |
| -------------------- | ----------------------------------------------------------------------- | ----- |
| attest               | `attest_cli` advertises JSON reports; schema to be read from `github.com/sahland/attest` | 1 |
| Lighthouse           | LHR is documented and typed in the Lighthouse repository                | 1     |
| axe                  | `axe.run` results object is documented in axe-core's API docs           | 2     |
| integration_test     | `TimelineSummary` keys are defined in Flutter's `timeline_summary.dart`, not in prose docs | 3 |
| flutter_lighthouse   | Unknown; 0.1.0 from `github.com/jayu1023/flutter_lighthouse`. Likely to need the maintainer's input | 3 |

## Consequences

- An adapter change ships with its fixture, so a reviewer can see the real input.
