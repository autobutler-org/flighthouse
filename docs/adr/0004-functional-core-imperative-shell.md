# 0004. Functional core, imperative shell

- Status: Accepted
- Date: 2026-10-06

## Context

The maintainer asked for a functional style: immutable data, sealed types with exhaustive matching, pure functions,
no shared mutable state, and side effects only at the edges. The pipeline is a natural fit, since every stage after
collection is a transformation of data.

## Decision

The pipeline is `collect -> parse -> normalize -> dedupe -> diff -> score -> render`.

| Stage     | Layer       | Shape                                                                      |
| --------- | ----------- | -------------------------------------------------------------------------- |
| collect   | `io/`       | `Config` -> raw artifacts on disk, effectful                                |
| parse     | `adapters/` | `RawArtifact -> Result<AdapterOutput, Failure>`                             |
| normalize | `pipeline/` | adapter output -> canonical findings (route, target, severity, category)  |
| dedupe    | `pipeline/` | findings -> findings unique by fingerprint, sources merged                 |
| diff      | `pipeline/` | `(findings, scores, Baseline) -> BaselineDiff`                              |
| score     | `pipeline/` | `(findings, measurements, ScoringConfig) -> Scores`                         |
| render    | `render/`   | `Report -> String`                                                          |

- Everything except `collect` is pure. The clock, environment, file contents, and tool versions are read in `io/`
  and passed in as values.
- `cli/` is the composition root. It reads, calls the pure pipeline, writes, and picks the exit code.
- Data is immutable: `final` fields, `const` constructors, collections made unmodifiable at construction.
- Domain types are sealed classes or records, consumed with exhaustive `switch` expressions with no `default`.
- No class hierarchy except the one a sealed type requires. No top-level or static mutable state.

## Consequences

- The whole pipeline is unit-testable with plain values. The end-to-end test is a pure function call plus file
  reads.
- `io/` takes its effects (`readFile`, `runProcess`, `now`) as function parameters with real defaults, so the shell
  is testable without a mocking library.
- `test/architecture_test.dart` fails if `dart:io` leaks into the core.
