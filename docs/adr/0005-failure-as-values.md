# 0005. Failure as values: an in-repo sealed Result

- Status: Accepted
- Date: 2026-10-06

## Context

Bad config, malformed tool output, and missing tools are expected, so the pipeline should model them as values.
The candidates, checked on pub.dev and GitHub on 2026-10-06:

| Package       | Latest | Last published | Notes                                                                 |
| ------------- | ------ | -------------- | --------------------------------------------------------------------- |
| `fpdart`      | 1.2.0  | 2025-10-29     | Broad FP toolkit (Option, Either, Task, IO, Reader, State, Do notation). Repo last pushed 2025-10-29. A v2 rewrite has been talked about for a long time. |
| `result_dart` | 2.2.0  | 2026-03-07     | Result type with async helpers. Smaller, single maintainer.           |
| `oxidized`    | 6.2.0  | 2024-07-23     | Rust-style Result and Option. Over two years without a release.       |
| `dartz`       | 0.10.1 | 2021-12-03     | Unmaintained.                                                         |

Dart 3 sealed classes, records, and exhaustive patterns make a Result type about 60 lines.

## Decision

Use an in-repo `sealed class Result<T, E>` with `Ok<T, E>` and `Err<T, E>` cases in `lib/src/result/`, with these
pure operations and nothing else until a caller needs more:

- `map`, `mapErr`, `flatMap`, `fold`
- `traverse`: `List<A>`, `A -> Result<B, E>` to `Result<List<B>, E>`, stopping at the first error
- `partition`: `List<Result<T, E>>` to `(List<T>, List<E>)`, for stages that should keep going past a bad
  artifact and report every failure

Errors are a `sealed class Failure` with one case per kind: `ConfigFailure`, `SchemaFailure` (with the JSON path),
`AdapterFailure`, `MissingToolFailure` (with the install hint), `IoFailure`, `ProcessFailure`. Each renders to one
line a user can act on.

## Consequences

- No dependency, no API churn from upstream, and the exported type is ours to keep stable in our public API.
- We do not get fpdart's async combinators. `io/` uses plain `Future<Result<T, Failure>>`, which needs no helpers.

## Alternatives considered

- **fpdart.** Well known, but over a year without a release, and most of its surface would go unused while all of it
  becomes part of our public API's vocabulary.
- **result_dart.** Reasonable, but a dependency for 60 lines of code we can own.
