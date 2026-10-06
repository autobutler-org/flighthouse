# 0018. Packaging for pub.dev

- Status: Accepted; repository URLs amended by [ADR 0020](0020-repository-in-autobutler-org.md)
- Date: 2026-10-06

## Context

The package should earn full pub points from the start. pana's documentation check passes only when at least 20% of
the public API has dartdoc comments: `createDocumentationCoverageSection` in pana's `lib/src/dartdoc/dartdoc.dart`
tests `ratio >= 0.2` (read on 2026-10-06). The brief also says: no comments anywhere in code. These conflict.

## Decision

pubspec metadata:

```yaml
name: flighthouse
description: >-
  Flutter accessibility, performance, Lighthouse-style report, and CI gate. Merges attest, Lighthouse,
  axe, and integration_test results into one scored report with a baseline diff.
repository: https://github.com/autobutler-org/flighthouse
issue_tracker: https://github.com/autobutler-org/flighthouse/issues
topics: [accessibility, a11y, performance, lighthouse, testing]
executables:
  flighthouse:
platforms:
  linux:
  macos:
  windows:
```

- The description stays within pana's 60 to 180 character range; checked by `make check/pana` in CI.
- Files: `LICENSE` (MIT), `CHANGELOG.md`, `README.md` with install, config, and CI usage, `example/` with a runnable
  example and a sample config, and `NOTICE` crediting Lighthouse for the ported scoring function
  ([ADR 0008](0008-scoring.md)).
- `platforms` lists native platforms only, because the CLI uses `dart:io`.
- CI fails if pana reports anything below full points.

## Dartdoc vs. no comments

The brief bans comments, but full pub points need dartdoc on at least 20% of the public API. Resolved on 2026-10-06:

- `///` dartdoc is allowed on declarations exported from `lib/flighthouse.dart` (and, in phase 3, the companion
  package's barrel), and nowhere else. It documents the API for users; it is not commentary on code.
- Every other comment, `//`, `/* */`, and `///` on anything not exported, stays banned.

Rejected: no comments at all, losing the documentation-coverage points.
