# [EPIC] Phase 3: integration_test frame timing and flutter_lighthouse

**Model scope: Opus.** It introduces the Flutter companion package and the first metric-scored categories.

## Goal

Responsiveness is scored from `integration_test` frame timing (`TimelineSummary`, or `watchPerformance` on web per
ADR 0032), flutter_lighthouse output is ingested (deferred, see task 5), and default metric control points are tuned
against quark.

## ADRs

0003 (companion package section), 0013, 0030 (the companion resolves outside the workspace), 0031 (the TimelineSummary
writer), and 0032 (web frame timing from `watchPerformance`) Accepted. A new ADR records the tuned control points.

## Tasks

1. **Create `packages/flighthouse_flutter`.** Resolves outside the root workspace (ADR 0030), pubspec metadata, its
   own pana run in CI.
   **Model scope: Sonnet.** Mirrors the root package's scaffolding.
2. **TimelineSummary writer.** A helper for integration tests that writes the summary JSON where `collect` expects
   it, named per route or scenario.
   **Model scope: Opus.**
3. **TimelineSummary adapter.** Docs first from Flutter's `timeline_summary.dart` at the version quark pins, fixtures
   from the repository's web fixture app run with `flutter drive -d chrome` (ADR 0032), not quark. Map frame metrics
   to responsiveness measurements.
   **Model scope: Opus.**
4. **Tune control points.** Run quark's integration tests repeatedly, look at the distribution, propose p10 and
   median per metric in an ADR.
   **Model scope: Opus.** Statistical judgment.
5. **flutter_lighthouse adapter.** Docs first from `github.com/jayu1023/flutter_lighthouse`. If its output format is
   undocumented, stop and ask the maintainer. Deferred in #34: its memory value is native-only and would read as a
   constant 0, a perfect score, on web ([evidence](../evidence/flutter-lighthouse-format.md)).
   **Model scope: Opus.**
6. **Run against quark and summarize.**
   **Model scope: Opus.**

## Open questions (answered)

- Which source provides memory? `TimelineSummary` reports GC counts but not heap size. Unless flutter_lighthouse
  covers it, memory stays "not measured" after phase 3. Is that acceptable, or is a memory collector in scope?
  Answered: memory stays "not measured" for web after phase 3 (ADR 0032, #34).
