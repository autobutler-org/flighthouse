# 0030. The Flutter companion resolves outside the workspace

- Status: Accepted
- Date: 2026-10-12

## Context

[ADR 0003](0003-package-layout.md) resolves `flighthouse` and `packages/flighthouse_flutter` as one Dart pub
workspace, with a fallback to separate resolution if the workspace causes trouble. Creating the companion (#30)
showed two problems with the workspace, both reproduced on 2026-10-12:

- With a stable Dart 3.13.5 SDK and no Flutter, `dart pub get` at the root fails with "Because flighthouse_flutter
  requires the Flutter SDK, version solving failed." A workspace resolves every member, so every Dart-only job
  breaks: the `Check` job in the `dart:stable` container, the Chrome smoke job in `web.yml` (`setup-dart`), and the
  `setup-dart` publish workflow behind `publish.yml`. Contributors to the core would need Flutter.
- A workspace has one shared resolution. `flutter_test` from Flutter 3.47.7 pins `test_api` 0.7.12, while the
  root's `test: ^1.32.0` needs `test_api` 0.7.14 or later, so version solving fails. The core's dev dependencies
  would have to follow Flutter's pins.

## Decision

- The root `pubspec.yaml` has no `workspace:` entry. `packages/flighthouse_flutter` has no
  `resolution: workspace` and resolves on its own with `flutter pub get`.
- When the companion starts to depend on `flighthouse`, it does so with a hosted constraint, and a gitignored
  `pubspec_overrides.yaml` with a path dependency during development, as ADR 0003's fallback says.
- The root's `analysis_options.yaml` excludes `packages/**`, so `dart analyze` at the root stays Dart-only. The
  companion's `analysis_options.yaml` includes the root's, so both packages follow one rule set.
- The companion takes `lints` as a dev dependency, which the shared rule set includes. This amends
  [ADR 0017](0017-dependency-policy.md)'s list of what `flighthouse_flutter` may depend on.
- Make targets: `setup/deps/flutter`, `check/flutter`, and `check/pana/flutter` need Flutter. `setup`, `check`, and
  `check/pana` include them. `check/pana/flighthouse` scores the core alone.
- CI: the `Check` job stays in the `dart:stable` container and runs the Dart-only targets. A separate `flutter` job
  in the same workflow sets up Flutter 3.47.7 and runs `check/flutter` and `check/pana/flutter`.

## Consequences

- The core builds, tests, and publishes with only a Dart SDK. `web.yml` and `publish.yml` are unchanged.
- The two packages are versioned and released together by convention, not by a shared lockfile.
- A local `make check` needs Flutter on `PATH`. The pre-commit hook already adds `~/flutter/bin`.
- Until the companion exists on `main`, pana cannot verify its `repository` URL and scores it 150/160.
- `dart pub publish` excludes workspace members from the root archive but not a nested package outside the
  workspace, so the `flighthouse` archive carries the companion's few files. An ignore rule cannot fix this: pub
  applies a `.pubignore` in `packages/` or the root to the companion's own publish too, which hides its pubspec.
  The root's analyzer exclude keeps those files out of the core's pana score.

## Alternatives considered

- **Keep the workspace and put Flutter in every job.** Rejected: every contributor and CI job would need Flutter,
  `publish.yml` would need a custom publish job, and the core's `test` version would follow Flutter's pin.
