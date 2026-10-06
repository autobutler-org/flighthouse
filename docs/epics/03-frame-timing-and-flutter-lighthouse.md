# [EPIC] Phase 3: integration_test frame timing and flutter_lighthouse

**Model scope: Opus.** It introduces the Flutter companion package and the first metric-scored categories.

## Goal

Responsiveness is scored from `integration_test` `TimelineSummary` output, flutter_lighthouse output is ingested,
and default metric control points are tuned against quark.

## ADRs

0003 (companion package section) and 0013 Accepted. A new ADR records the tuned control points.

## Tasks

1. **Create `packages/flighthouse_flutter`.** Workspace member, pubspec metadata, its own pana run in CI.
   **Model scope: Sonnet.** Mirrors the root package's scaffolding.
2. **TimelineSummary writer.** A helper for integration tests that writes the summary JSON where `collect` expects
   it, named per route or scenario.
   **Model scope: Opus.**
3. **TimelineSummary adapter.** Docs first from Flutter's `timeline_summary.dart` at the version quark pins, fixtures
   from a real quark integration test. Map frame metrics to responsiveness measurements.
   **Model scope: Opus.**
4. **Tune control points.** Run quark's integration tests repeatedly, look at the distribution, propose p10 and
   median per metric in an ADR.
   **Model scope: Opus.** Statistical judgment.
5. **flutter_lighthouse adapter.** Docs first from `github.com/jayu1023/flutter_lighthouse`. If its output format is
   undocumented, stop and ask the maintainer.
   **Model scope: Opus.**
6. **Run against quark and summarize.**
   **Model scope: Opus.**

## Open questions

- Which source provides memory? `TimelineSummary` reports GC counts but not heap size. Unless flutter_lighthouse
  covers it, memory stays "not measured" after phase 3. Is that acceptable, or is a memory collector in scope?
