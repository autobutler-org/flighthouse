# Changelog

## 0.2.0

- Initial release of the Flutter companion package.
- `writeTimelineSummary` writes an integration test's `TimelineSummary` summary JSON to
  `build/flighthouse/timeline/<name>.timeline_summary.json`, where `flighthouse collect` reads it once
  `sources.timeline.dir` points there.
