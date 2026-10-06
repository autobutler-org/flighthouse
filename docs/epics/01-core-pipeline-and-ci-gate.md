# [EPIC] Phase 1: core pipeline, attest and Lighthouse adapters, CI gate

**Model scope: Opus.** It sets the schema, scoring, and failure model every later phase builds on.

## Goal

`flighthouse ci` reads attest and Lighthouse outputs, produces `report.json` and a self-contained `report.html`, diffs
against a committed baseline, and exits non-zero only on new findings or score drops past the threshold. The package
is pub.dev-ready with full pana points, and it has produced a real report for quark.

## ADRs

All Accepted on 2026-10-06: 0003, 0005, 0006, 0007, 0008, 0009, 0010, 0011, 0012, 0013, 0017, 0018, 0019.

## Tasks

Ordered bottom to top. Tasks 2 to 8 are pure and can run in parallel once task 3 lands.

1. **Scaffold the package.** pubspec with ADR 0018 metadata, `LICENSE`, `CHANGELOG.md`, `README.md`, `NOTICE`,
   `example/`, `bin/flighthouse.dart` stub, `test/architecture_test.dart`, `.github/workflows/check.yml`,
   Dependabot for `pub`. Confirm `dart pub publish --dry-run` from the workspace root (ADR 0003 open question) and
   `make check/pana` at full points.
   **Model scope: Sonnet.** Mechanical, every value is specified in ADRs 0003, 0018, and 0019.
2. **Result and Failure.** `lib/src/result/` per ADR 0005, with `map`, `mapErr`, `flatMap`, `fold`, `traverse`,
   `partition`, and the sealed `Failure` cases with their one-line messages. Unit tests for every operation.
   **Model scope: Sonnet.** Fully specified in ADR 0005, no design judgment left.
3. **Core schema.** Every type in ADR 0006 with validating `fromJson` returning `SchemaFailure` with a JSON path,
   deterministic `toJson`, round-trip tests, and one malformed-input test per required field.
   **Model scope: Opus.** Validation and error paths across a dozen types.
4. **Fingerprints and route normalization.** ADR 0007: canonical fingerprint, field escaping, route pattern
   matching in go_router syntax. Property-style tests that normalization is idempotent.
   **Model scope: Opus.** Correctness here decides whether the gate is usable.
5. **Configuration.** `flighthouse.yaml` parser per ADR 0010: defaults, unknown-key rejection, YAML span locations
   in failures, weight-sum and control-point validation.
   **Model scope: Opus.** Error reporting design.
6. **Scoring.** Exact port of Lighthouse's `getLogNormalScore` and `erf` with Lighthouse's own test vectors; rule
   scores, category and overall scores, renormalization over measured categories (ADR 0008). Confirm the 10/7/3
   weights against Lighthouse's `default-config.js`.
   **Model scope: Opus.** Numerical parity with an external implementation.
7. **Baseline diff and gate.** ADR 0009: pure diff, gate evaluation, deterministic baseline serialization, the
   missing-category and fingerprint-version rules.
   **Model scope: Opus.** Gate semantics decide whether teams keep it on.
8. **Renderers.** JSON renderer, and the self-contained HTML renderer with gauges, findings, and new-finding flags
   (ADR 0012). Golden tests.
   **Model scope: Opus.** The HTML report needs design judgment.
9. **attest adapter.** Docs first: read `attest_cli` and `attest_flutter` docs and source at
   `github.com/sahland/attest`, record fixtures from a real run with `SOURCE.md`, then parse. Stop and ask if the
   JSON format is undocumented.
   **Model scope: Opus.** Unfamiliar format, mapping decisions.
10. **Lighthouse adapter.** Docs first: LHR types from the Lighthouse repository, fixtures from a real
    `lighthouse --output=json` run. Map categories and audits to findings, rule outcomes, and tool-scored
    measurements.
    **Model scope: Opus.** Large format, mapping decisions.
11. **Shell and CLI.** `io/` file reading and writing, clock, git commit lookup, and the four commands with exit
    codes (ADR 0011). In phase 1, `collect` copies configured tool outputs into `<reportDir>/raw/`.
    **Model scope: Opus.** Composition root, error mapping.
12. **End-to-end test.** Full pipeline on recorded attest and Lighthouse fixtures, golden `report.json` and
    `report.html`, and `make test/cli` wired into CI.
    **Model scope: Sonnet.** Wiring existing pieces against fixtures that already exist.
13. **Run against quark.** Build quark's web app, run Lighthouse on its public routes, gather attest output, run
    `flighthouse report` and `ci`, and show the maintainer the real report.
    **Model scope: Opus.** Real-world debugging across two repositories.
14. **Phase summary.** What works, what was assumed, what could not be verified.
    **Model scope: Opus.** Judgment about what is actually proven.

## Exit criteria

- `make check`, `make test`, `make test/cli`, and `make check/pana` (full points) pass in CI on a Dart-only image.
- A real `report.html` for quark has been shown to the maintainer.
- Every ADR in the list above is Accepted, and every assumption made along the way is written down.

## Open questions

- quark does not use attest today. Getting real attest output means adding `attest_flutter` to quark's tests, which
  is a change to quark. Approve that, or should phase 1 run against quark with Lighthouse only?
- Most quark routes need sign-in. Phase 1 can run Lighthouse on public routes only (`/login`, `/setup`, `/terms`);
  authenticated routes wait for the phase 2 runner. Acceptable?
