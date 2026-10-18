# Changelog

## Unreleased

- `writeFrameTimingSummaries` writes the `watchPerformance` reports in an integration test's response data to
  `build/flighthouse/timeline/<reportKey>.frame_timing_summary.json`. It is the frame timing source for Flutter
  web, where `traceAction` and so `TimelineSummary` are not available.

## 0.2.0

- Initial release of the Flutter companion package.
- `writeTimelineSummary` writes an integration test's `TimelineSummary` summary JSON to
  `build/flighthouse/timeline/<name>.timeline_summary.json`, where `flighthouse collect` reads it once
  `sources.timeline.dir` points there.
