# 0009. Baseline diff and CI gate

- Status: Accepted; new-finding rule superseded for Lighthouse metric findings by ADR 0027
- Date: 2026-10-06

## Context

The `ci` command must exit non-zero only on new findings or on score drops past a configured threshold. Existing
findings in a legacy app must not block every PR, or the gate gets removed.

`attest_cli` has its own baseline-diff gate. flighthouse diffs at the unified level, across all sources, so it does
not use attest's baseline.

## Decision

- The baseline is a committed JSON file (default `flighthouse-baseline.json`): `schemaVersion`, `fingerprintVersion`,
  per-category scores, overall score, and the baselined findings with source, category, severity, rule, route, and
  target. The extra fields make the file reviewable in a PR diff. It is written with sorted keys and sorted entries,
  so regenerating it unchanged produces no diff.
- `diff(findings, scores, baseline)` is pure and returns `new`, `fixed`, and `persisting` findings, plus a score
  delta per category and overall.
- The gate fails when either:
  - a `new` finding has severity at or above `gate.minSeverity` (default `minor`, so any new finding except `info`
    fails); or
  - a category or the overall score dropped by more than its `gate.maxScoreDrop` in points (defaults: overall 2,
    perf 5, every other category 2). Perf gets more room because Lighthouse perf varies run to run.
- `fixed` findings never fail the gate. The output suggests `flighthouse baseline --update`.
- A baseline with a different `fingerprintVersion` is refused with a message to run `baseline --update`.
- A category measured now but missing from the baseline is reported and does not fail. A category in the baseline
  but missing now fails, because a collector silently dropping out is the regression we most need to catch.
- Exit codes: `0` passed, `1` gate failed, `2` usage or config error, `3` input or external tool error.

## Consequences

- Adopting flighthouse on an existing app is: run `baseline --update`, commit, turn on `ci`.

## Open questions

- Are the default thresholds right? Perf's 5 points is a guess at Lighthouse variance until we measure quark.
