# 0003. Package layout: Flutter-free core, Flutter companion

- Status: Accepted
- Date: 2026-10-06

## Context

- The CLI must run on any CI image that has a Dart SDK, installed with `dart pub global activate flighthouse`. A
  Flutter SDK dependency would break that.
- Some helpers need `flutter_test` or `integration_test`, for example writing `TimelineSummary` JSON from an
  integration test.
- The name `flighthouse` is free on pub.dev: `GET https://pub.dev/api/packages/flighthouse` returned 404 on
  2026-10-06.
- The repository is `github.com/brandonapol/flighthouse`.

## Decision

Two packages in one repository, resolved as a Dart pub workspace.

```text
pubspec.yaml                    package flighthouse, workspace root
bin/flighthouse.dart            executable, declared under `executables:`
lib/flighthouse.dart            public barrel: model, config, pipeline, render, Result
lib/src/result/
lib/src/model/
lib/src/config/
lib/src/adapters/<tool>/
lib/src/pipeline/
lib/src/render/
lib/src/io/                     the only place with dart:io, processes, the browser
lib/src/cli/
example/
test/                           mirrors lib/src; test/fixtures/<tool>/<tool-version>/
packages/flighthouse_flutter/   companion, depends on flutter_test and integration_test
```

- `flighthouse` depends on no Flutter package, directly or transitively.
- `flighthouse_flutter` depends on `flighthouse` for the schema and on Flutter for the test bindings. It is created
  in phase 3, when the first helper that needs Flutter is written, not before.
- The public barrel exports the schema, config, pipeline, renderers, and `Result`, so other tools can embed the
  pipeline without the CLI. `io/` and `cli/` are not exported.
- `test/architecture_test.dart` enforces the layering by scanning imports.

## Consequences

- `dart pub global activate flighthouse` pulls in no Flutter.
- Two packages to version and publish once phase 3 lands. They share a CHANGELOG convention and are released
  together.

## Alternatives considered

- **One package with a `flighthouse/flutter.dart` library inside it.** Rejected: pubspec dependencies are
  per-package, so `flutter_test` would become a dependency of the CLI.
- **Two independent repositories.** Rejected: the companion needs the schema, and cross-repo changes to it would
  need lockstep releases.

## Open questions

- Publishing a package that is also a workspace root has to be confirmed with `dart pub publish --dry-run` in the
  first phase 1 task. If it fails, the fallback is the same layout without `workspace:`, with the companion using
  a `pubspec_overrides.yaml` path dependency during development.
