# Quickstart: frame timing

This guide takes a Flutter app from nothing to a `responsiveness` finding built from its own frame timings. An
`integration_test` measures a scenario with `watchPerformance`, the driver writes the report with
`flighthouse_flutter`'s `writeFrameTimingSummaries`, and `flighthouse collect` reads the directory it was written
to. It works on Flutter web, where `traceAction` cannot record a `TimelineSummary`.

The format and the writer are decided in [ADR 0032](adr/0032-web-frame-timing-source.md). The worked example is the
web fixture: [`integration_test/perf_test.dart`](../integration/web_fixture/integration_test/perf_test.dart) measures
two routes and [`test_driver/perf_test.dart`](../integration/web_fixture/test_driver/perf_test.dart) writes them. Its
[README](../integration/web_fixture/README.md#frame-timing) has the commands, and
[`test/fixtures/timeline/3.47.7/`](../test/fixtures/timeline/3.47.7/SOURCE.md) holds what one CI run recorded.

## Prerequisites

| Tool | Version | Needed by |
| --- | --- | --- |
| Flutter | 3.47.7 stable, the version the recorded fixtures come from | `flutter drive` |
| Chrome and a matching `chromedriver` on port 4444 | the recording used Chrome and ChromeDriver 155.0.8059.39 | `flutter drive` on web |
| flighthouse | see [Install flighthouse](quickstart-web.md#install-flighthouse) | `collect`, `report`, `ci` |

flighthouse itself only reads the files. It does not run `flutter drive`, Chrome, or chromedriver.

## Add the dependencies

The test needs `integration_test`, the driver needs `flutter_driver`, and the writer is in `flighthouse_flutter`.
All three are dev dependencies:

```yaml
dev_dependencies:
  flighthouse_flutter: ^0.2.0
  flutter_driver:
    sdk: flutter
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
```

`flutter pub add --dev flighthouse_flutter` adds the first line.

## Measure a scenario with `watchPerformance`

Put the test in `integration_test/`. Each `watchPerformance` call collects the frames drawn while its action runs
and reports them under `reportKey`. That key names the scenario: it becomes the file name and the route of every
finding. It must start with a letter or digit and contain only letters, digits, `.`, `_`, and `-`, so a URL path
such as `/perf/control` has to be turned into `perf-control` first.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:my_app/main.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('scrolls the file list', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await binding.watchPerformance(() async {
      await tester.fling(find.byType(ListView), const Offset(0, -500), 1000);
      await tester.pumpAndSettle();
    }, reportKey: 'files-scroll');
  });
}
```

The fixture's test loops over two routes and pushes each one inside the action, with the keys `perf-control` and
`perf-janky`. Each `watchPerformance` call waits at least 4 seconds for the frame timings to arrive, so every
scenario adds that to the run.

## Write the reports from the driver

Put the driver in `test_driver/`. It runs on the host, receives the test's report data, and writes every
`watchPerformance` report to `build/flighthouse/timeline/<reportKey>.frame_timing_summary.json`. Set
`FLUTTER_TEST_OUTPUTS_DIR` to move `build`, or pass `directory:`.

```dart
import 'package:flighthouse_flutter/flighthouse_flutter.dart';
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    final result = await writeFrameTimingSummaries(data);
    for (final write in result.writes) {
      switch (write) {
        case TimelineSummaryWritten():
          break;
        case TimelineSummaryWriteFailed(:final path, :final reason):
          throw StateError('could not write $path: $reason');
      }
    }
    if (result.writes.isEmpty) {
      throw StateError('no frame timing reports; skipped ${result.skipped}');
    }
  },
);
```

Report data entries that are not `watchPerformance` reports are not written; their keys are listed in
`result.skipped`. A file system error comes back as `TimelineSummaryWriteFailed` instead of being thrown. A
`reportKey` that breaks the name rule above throws an `ArgumentError`. The fixture's driver fails unless exactly its
two reports were written, which catches a scenario that silently stopped reporting.

## Run the test

Start chromedriver, then drive the test from the app's root directory:

```sh
chromedriver --port=4444 &
flutter drive -d chrome --driver=test_driver/perf_test.dart --target=integration_test/perf_test.dart
```

On a machine without a display, such as a CI runner, use the `web-server` device with headless Chrome. This is the
command the fixtures were recorded with:

```sh
flutter drive -d web-server --browser-name=chrome --headless \
  --driver=test_driver/perf_test.dart \
  --target=integration_test/perf_test.dart
```

[`record-timeline.yml`](../.github/workflows/record-timeline.yml) runs it on GitHub Actions, including the
system libraries Chrome needs.

`writeFrameTimingSummaries` overwrites the files it writes and leaves the others. Delete
`build/flighthouse/timeline/` before a run when a scenario was renamed or removed, or `collect` keeps reading its
old file.

## Point flighthouse at the directory

Add the directory to `flighthouse.yaml` under `sources.timeline.dir`. A relative path resolves against the config
file's directory:

```yaml
app: my_app
sources:
  timeline:
    dir: build/flighthouse/timeline
```

`timeline` can sit next to a `web:` section, so one `collect` runs Lighthouse and axe and also imports the frame
timings. Point `dir` only at the directory the driver writes: every `.json` file in it must be named
`<scenario>.frame_timing_summary.json`.

## Collect and report

```sh
flighthouse collect
flighthouse report
```

`collect` replaces `<reportDir>/raw/timeline/` (`.flighthouse/raw/timeline/` by default) with a copy of the `.json`
files in `sources.timeline.dir`. `report` reads that copy. With the two recorded fixture files in the directory,
the output is:

```text
collected 2 timeline files
my_app: overall n/a | a11y n/a | perf n/a | responsiveness n/a | memory n/a | best-practices n/a
wrote .flighthouse/report.json, .flighthouse/report.html
```

and `report.json` holds four `responsiveness` findings:

| Severity | Rule | Route | Message |
| --- | --- | --- | --- |
| critical | `frame-build-budget` | `perf-janky` | 17 of 17 frames missed the 16 ms build budget; the average build time was 124.5 ms |
| minor | `frame-rasterizer-budget` | `perf-janky` | 1 of 17 frames missed the 16 ms raster budget; the average raster time was 11.0 ms |
| moderate | `frame-build-budget` | `perf-control` | 1 of 2 frames missed the 16 ms build budget; the average build time was 18.3 ms |
| moderate | `frame-rasterizer-budget` | `perf-control` | 1 of 2 frames missed the 16 ms raster budget; the average raster time was 24.5 ms |

The scores stay `n/a` until the metrics have control points; see [Score and gate](#score-and-gate).

## What the findings mean

Each scenario gives at most two findings, one per phase: `frame-build-budget` for the UI thread building the frame
and `frame-rasterizer-budget` for drawing it. The severity comes from the phase's average time against the 16 ms
frame budget:

| Average time for the phase | Severity |
| --- | --- |
| over 4 budgets (64 ms, under 15 fps) | critical |
| over 2 budgets (32 ms, under 30 fps) | serious |
| over 1 budget (16 ms, under 60 fps) | moderate |
| within budget, but some frames missed it | minor |
| within budget, no frame missed it | no finding |

Jank from your own Dart code shows up in build time. The fixture's `/perf/janky` route blocks the main thread for
120 ms every frame: its build phase averages 124.5 ms and is critical, while its raster phase averages 11.0 ms and
is minor. Start with the build finding, and look at what the widgets on that route do while the scenario runs.

Read the numbers with care on web:

- The browser coarsens `performance.now()`, so web frame times are coarser than device times.
- A scenario that draws very few frames is dominated by its first frame. The fixture's control route draws 2 frames
  and still gets two moderate findings. Measure an action that draws enough frames to be representative, such as a
  scroll or an animation.
- The summary's GC counts and layer and picture cache values are checked but not measured; the web engine does not
  report them, so `memory` stays `n/a`.

Every finding also records its phase's average time as its metric, and `report.json` lists all ten timing values per
scenario as measurements: the average, 90th percentile, 99th percentile, and worst build and raster times in ms,
and the two missed-budget counts.

## Score and gate

A frame timing measurement counts toward the `responsiveness` score only when `scoring.metrics` gives its metric
log-normal control points: a value at `p10` scores 90 and a value at `median` scores 50. The metric names are the
summary's keys, such as `average_frame_build_time_millis`. flighthouse ships no control points for them yet (tuning
them is #33), so these values only show the shape:

```yaml
scoring:
  metrics:
    average_frame_build_time_millis: {p10: 16, median: 32}
    average_frame_rasterizer_time_millis: {p10: 16, median: 32}
```

With these, the baseline from `perf-control` alone scores `responsiveness` 76.9. Adding `perf-janky` and running
`ci` fails on the score drop:

```text
my_app: overall 63 | a11y n/a | perf n/a | responsiveness 63 | memory n/a | best-practices n/a
2 new, 0 fixed, 2 unchanged
FAIL responsiveness score dropped from 76.9 to 63, more than the allowed 2 points
FAIL overall score dropped from 76.9 to 63, more than the allowed 2 points
gate failed
```

Frame timing findings carry a metric, so by default a new one does not fail `ci` by itself; only the score drop
does, and `gate.maxScoreDrop.responsiveness` (2 points by default) sets how far it may fall. To also fail on each new
finding at or above `gate.minSeverity`, set:

```yaml
gate:
  metricFindings: new
```

Without control points and without `metricFindings: new`, `ci` reports the new findings but passes. The rest of
the gate, the baseline, and the exit codes work as in the
[web quickstart](quickstart-web.md#the-baseline).

## Troubleshooting

#### `could not list build/flighthouse/timeline: No such file or directory`

`collect` found no directory at `sources.timeline.dir`. Run `flutter drive` first, and check that `dir` matches
where the driver wrote, including `FLUTTER_TEST_OUTPUTS_DIR` or `directory:` if you set either.

#### `timeline: .flighthouse/raw/timeline: no .json outputs found`

The directory exists but holds no summaries. Check `result.skipped` in the driver: a test that never called
`watchPerformance`, or a driver whose callback did not call `writeFrameTimingSummaries`, writes nothing.

#### `… is not named <scenario>.frame_timing_summary.json or <scenario>.timeline_summary.json`

Another JSON file is in `sources.timeline.dir`, for example `integration_response_data.json` from Flutter's default
driver callback. Point `dir` at the directory `writeFrameTimingSummaries` writes, not at `build`.

#### `TimelineSummary output is not read yet; write frame timing with watchPerformance and writeFrameTimingSummaries instead`

A `<name>.timeline_summary.json` from `writeTimelineSummary` is in the directory. Only `watchPerformance` summaries
are scored today. Measure with `watchPerformance` as above.

#### `Invalid argument (name): must start with a letter or digit and contain only letters, digits, ".", "_", and "-": …`

A `reportKey` breaks the name rule. Use only letters, digits, `.`, `_`, and `-`, starting with a letter or digit.
