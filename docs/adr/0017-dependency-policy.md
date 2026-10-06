# 0017. Dependency policy

- Status: Accepted
- Date: 2026-10-06

## Context

Dependencies must be minimal, well maintained, and each one justified. Versions and dates are from the pub.dev API
on 2026-10-06.

## Decision

Runtime dependencies of `flighthouse`:

| Package     | Version | Publisher | Why                                                                     |
| ----------- | ------- | --------- | ----------------------------------------------------------------------- |
| `args`      | 2.7.0   | Dart team | CLI parsing; named in the brief.                                        |
| `yaml`      | 3.1.4   | Dart team | Config parsing with source spans for error messages.                    |
| `crypto`    | 3.0.7   | Dart team | SHA-256 for fingerprints. `dart:convert` has no hash.                   |
| `path`      | 1.9.1   | Dart team | Cross-platform path handling in `io/`.                                  |
| `puppeteer` | 3.26.0  | community | Phase 2 only, and only once [ADR 0015](0015-browser-automation-and-axe.md) is accepted. Imported only from `lib/src/io/`. |

Dev dependencies: `test` (1.32.0) and `lints` (6.1.0), both Dart team. `pana` is run with `dart pub global run`, not
declared.

Not used, and why:

- `fpdart`, `result_dart`, `dartz`: see [ADR 0005](0005-failure-as-values.md).
- `json_serializable`, `freezed`, `build_runner`: code generation, and generated parsers throw.
- Template engines: the HTML renderer is plain string building.
- `glob`: sources are directories ([ADR 0010](0010-configuration.md)).
- `very_good_analysis`: `lints` plus the strict modes and an explicit rule list in `analysis_options.yaml` is
  enough, and keeps the rule set reviewable in one file.
- `http`: nothing in phases 1 to 3 needs it. The axe download in phase 2 uses `dart:io` `HttpClient`.

Rules:

- Adding a dependency means updating this table first, in the same PR.
- Constraints are caret ranges on the latest release. Dependabot opens `pub` update PRs weekly.
- `flighthouse` never depends on Flutter. `flighthouse_flutter` may depend on `flutter`, `flutter_test`, and
  `integration_test`, nothing else without an entry here.
