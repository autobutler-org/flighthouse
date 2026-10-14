# 0031. The TimelineSummary writer

- Status: Accepted (by the implementer under the maintainer's go-ahead for #31; flagged for review in PR); writer input extended by [ADR 0032](0032-web-frame-timing-source.md)
- Date: 2026-10-13

## Context

Phase 3 task 2 (#31) asks `flighthouse_flutter` for a helper that an integration test calls to write a
`TimelineSummary`'s summary JSON where `flighthouse collect` picks it up, named per route or scenario. Three points
were open.

- **The type lives in `flutter_driver`.** `TimelineSummary` is declared in Flutter's
  `packages/flutter_driver/lib/src/driver/timeline_summary.dart` and exported only by
  `package:flutter_driver/flutter_driver.dart`. `integration_test` depends on `flutter_driver` but re-exports only
  `testOutputsDirectory` from it. [ADR 0017](0017-dependency-policy.md) lets the companion depend on `flutter`,
  `flutter_test`, and `integration_test`, nothing else.
- **Where `collect` reads.** `collect` copies the `*.json` files from `sources.timeline.dir` into
  `<reportDir>/raw/timeline/` ([ADR 0010](0010-configuration.md), [ADR 0011](0011-cli.md)). No default exists for
  that directory, and the writer runs in the driver process, which does not read `flighthouse.yaml`. Flutter's own
  `TimelineSummary.writeTimelineToFile` writes `<name>.timeline.json`, the full trace, and
  `<name>.timeline_summary.json` to `testOutputsDirectory`, which is `build` unless `FLUTTER_TEST_OUTPUTS_DIR` is
  set. Pointing `sources.timeline.dir` at `build` would collect the full traces and any other JSON there too.
- **Failure handling.** The core returns `Result<T, Failure>` ([ADR 0005](0005-failure-as-values.md)). The companion
  does not depend on `flighthouse` yet, and `flighthouse` 0.2.0, the version it would need, is not on pub.dev.
  `TimelineSummary.summaryJson` throws a `StateError` when the timeline has no frame events, and writing a file can
  throw a `FileSystemException`.

## Decision

- `flighthouse_flutter` depends on `flutter_driver` from the Flutter SDK (`sdk: flutter`). It adds nothing to an
  app's resolution that `integration_test` does not already bring. This amends ADR 0017's list for the companion.
- `writeTimelineSummary(summary, name: ...)` writes `summary.summaryJson`, unchanged and encoded the way Flutter
  encodes it, to `<directory>/<name>.timeline_summary.json`. The suffix matches Flutter's own summary file, so the
  TimelineSummary adapter (#32) reads either.
- `directory` defaults to `<testOutputsDirectory>/flighthouse/timeline`, so `build/flighthouse/timeline` by
  default. A project sets `sources.timeline.dir` to that path. Only summaries go there, so `collect` copies nothing
  else.
- `name` is the route or scenario, chosen by the test. It must be a plain file name: letters, digits, `.`, `_`, and
  `-`, starting with a letter or digit. Anything else is a programmer error and throws `ArgumentError`, because the
  name is a literal in test code.
- The helper returns a sealed `TimelineSummaryWrite`: `TimelineSummaryWritten` with the path, or
  `TimelineSummaryWriteFailed` with the path and a reason. An empty timeline and a file system error are values,
  never thrown. When the companion starts to depend on `flighthouse` ([ADR 0030](0030-companion-resolves-separately.md)),
  this type can move to the core's `Result` and `Failure`.

## Consequences

- The companion's barrel imports `dart:io` through `flutter_driver`, so it runs in the driver process on the host,
  where `integrationDriver`'s `responseDataCallback` runs, and not inside the app under test.
- Until #32 adds a default, a project configures `sources.timeline.dir` by hand.
- A test that ignores the returned value does not fail when the write fails. The README shows the `switch` that
  fails the run.

## Alternatives considered

- **Take `summaryJson` as a `Map` and avoid `flutter_driver`.** Rejected: the issue asks for a helper that takes a
  `TimelineSummary`, and a `Map` parameter accepts anything.
- **Depend on `flighthouse` for `Result` and `Failure` now.** Rejected for this task: 0.2.0 is unpublished, a caret
  on 0.1.0 excludes 0.2.0, and CI has no `pubspec_overrides.yaml`.
- **Write straight into `.flighthouse/raw/timeline`.** Rejected: `collect` deletes and refills that directory from
  `sources.timeline.dir`, and the writer cannot see a non-default `reportDir`.
