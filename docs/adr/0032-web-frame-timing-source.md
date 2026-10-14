# 0032. Web frame timing from watchPerformance

- Status: Accepted by delegated Opus review, 2026-10-13; maintainer may revert
- Date: 2026-10-13

## Context

Phase 3 scores responsiveness from `integration_test` frame timing (#32). Quark, the first target, ships only as a
web app. Everything below was read from the Flutter SDK at 3.47.7 (framework revision `abaf9c5237`), the version
quark pins. Nothing has been run against a real build yet.

- **`traceAction` cannot run on web.** `IntegrationTestWidgetsFlutterBinding.traceAction` calls `traceTimeline`,
  which calls `enableTimeline` (`packages/integration_test/lib/integration_test.dart`). That connects to the Dart VM
  service from `developer.Service.getInfo()`, and a web build has no VM service. Without a trace there is no
  `TimelineSummary`, so the format [ADR 0031](0031-timeline-summary-writer.md) writes cannot come from quark's
  target.
- **`watchPerformance` uses no VM service.** It registers `addTimingsCallback`, runs the action, and passes the
  collected `FrameTiming`s to `FrameTimingSummarizer` (`packages/flutter_test/lib/src/frame_timing_summarizer.dart`).
  It stores `FrameTimingSummarizer.summary` in `reportData[reportKey]`, where `reportKey` defaults to
  `performance`.
- **The web engine reports `FrameTiming`.** `lib/web_ui/lib/src/engine/frame_timing_recorder.dart` records vsync,
  build start and finish, and raster start and finish with `performance.now()`. It sends them to `onReportTimings`
  about every 100 ms.
- **The summary is a subset of `TimelineSummary.summaryJson`.** `FrameTimingSummarizer.summary` has the following
  keys, all also present in `summaryJson` under the same names and units:
  - frame build and raster time in ms (average, 90th and 99th percentile, worst) and their missed-budget counts;
  - `frame_count`;
  - `frame_build_times` and `frame_rasterizer_times` in µs;
  - layer and picture cache counts, and their memory in MB;
  - `new_gen_gc_count` and `old_gen_gc_count`.

  It has none of the vsync-lag, refresh-rate, GPU, `total_ui_gc_time`, frame-request-latency, or begin-time keys.
- **Some values are not measured on web.** When `kIsWeb`, `_runAndGetGCInfo` skips tracing and returns zero GC
  counts. The web recorder fills in only the five timestamps of a `FrameTiming`, so the layer and picture cache
  values are presumably always zero too. `performance.now()` resolution is coarsened by the browser; the engine's
  own comment on `_nowMicros` points to MDN on this. The exact resolution in the Chrome used by CI has not been
  checked.
- **The summary reaches the host as response data.** `integrationDriver` passes the test's `reportData` to its
  `responseDataCallback`. The default callback, `writeResponseData`, writes every key into a single
  `<testOutputsDirectory>/integration_response_data.json`. ADR 0031's `writeTimelineSummary` takes a
  `TimelineSummary`, and the driver process never has one on this path. ADR 0031 also rejected a `Map` parameter
  because a `Map` accepts anything.

## Decision

- **One source, two formats.** Frame timing stays under the existing `timeline` source
  ([ADR 0006](0006-core-schema.md)) and `sources.timeline.dir`. The adapter picks the format from the file
  name. `<name>.timeline_summary.json` is a `TimelineSummary`. `<name>.frame_timing_summary.json` is a
  `FrameTimingSummarizer` summary. Any other `*.json` in the directory is an `AdapterFailure` naming the file.
- **Shared frame metrics.** Both formats map to the same responsiveness measurements, using the keys they have in
  common: frame build and raster time and their missed-budget counts. Keys only `TimelineSummary` has are read only
  from that format. A key a format is defined to have but that is missing or has the wrong type is an
  `AdapterFailure` naming the JSON path.
- **Web values that are not measured are not scored.** In a `frame_timing_summary`, the GC counts and the layer and
  picture cache values produce no measurement. They are not read as zero. This keeps memory "not measured" for web
  (epic open question).
- **A second writer that takes the response data.** `flighthouse_flutter` adds
  `writeFrameTimingSummaries(responseData, ...)` for use as, or inside, `integrationDriver`'s
  `responseDataCallback`.
  - Each entry of `responseData` whose value has the `FrameTimingSummarizer` summary's required keys is written
    unchanged to `<directory>/<key>.frame_timing_summary.json`.
  - The test names a scenario by passing it as `watchPerformance`'s `reportKey`. The name rule from ADR 0031
    applies to the key.
  - `directory` defaults to the same `<testOutputsDirectory>/flighthouse/timeline` as ADR 0031.
  - An entry without those keys is skipped, and the returned value lists it. The `Map` is checked against the
    summary's shape, which answers ADR 0031's objection to a bare `Map`.
  - The result is a sealed value with the same written and failed cases as ADR 0031. Nothing is thrown except the
    name `ArgumentError`.
- **ADR 0031 is amended, not rewritten.** ADR 0031 stays the decision for `TimelineSummary` input. This ADR adds the
  second writer and the second file suffix. When this ADR is accepted, ADR 0031's status line gets "writer input
  extended by 0032". Its Decision section is not touched.
- **Fixtures come from the repository's web fixture app.** `integration/web_fixture` hosts the
  `watchPerformance` integration test and its `test_driver`. Before the adapter is written, that test is run once
  with `flutter drive -d chrome`. The real output is stored under `test/fixtures/timeline/3.47.7/` with a
  `SOURCE.md` ([ADR 0013](0013-adapter-contract.md)) giving the command and the Chrome version. Quark is not a
  prerequisite for the adapter's fixtures.
- **The fixture app is extended in separate tickets.** `integration/web_fixture` has no `integration_test` or
  `test_driver` today, and no `integration_test` or `flutter_driver` dependency. Adding them is follow-up work,
  filed separately and outside the PR that carries this ADR.

## Consequences

- Web apps, quark included, get responsiveness measurements without a mobile device or a desktop target.
- The adapter and its fixtures depend only on this repository. Measuring quark itself later still needs an
  `integration_test` and a `test_driver` in quark that use `watchPerformance`. Neither exists today.
- Web frame times are coarser than device times. Control points tuned in #33 apply to web runs, and a `TimelineSummary`
  from a device should not be compared against them without checking.
- Memory stays unmeasured for web after phase 3, unless flutter_lighthouse (#34) covers it.
- `watchPerformance` waits at least 4 s per call while `FrameTiming`s flush, so each scenario adds that to the run.

## Alternatives considered

- **Have the adapter read `integration_response_data.json` and use no new writer.** Rejected: the file has a fixed
  name in `build/` next to other JSON. It holds every key the test reported, not only frame timing. A project would
  have to point `sources.timeline.dir` at `build`, which ADR 0031 already rejected.
- **A separate source, for example `frame-timing`.** Rejected: both formats measure the same frames with the same
  keys. A second source would duplicate the config key, the measurement names, and the control points.
- **Take a `FrameTimingSummarizer` in the writer.** Not possible: the summarizer is built inside the app under test.
  The driver process only receives its `summary` as decoded JSON.
- **Record on a device or a desktop build instead (`traceAction`).** Not chosen by the maintainer: quark has no
  desktop target, and no device is available in the development environment.

## Open questions

- Are the cache values always zero on web, or does a renderer fill them? To be confirmed from the first recording.
- Does `reportData` from a web `flutter drive` run reach `responseDataCallback` intact? The source points that way,
  but it has not been run.
