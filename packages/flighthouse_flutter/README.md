# flighthouse_flutter

Flutter test helpers for [flighthouse](https://pub.dev/packages/flighthouse), the Lighthouse-style scored report
and CI gate for Flutter apps.

> **Status: pre-release.** The `TimelineSummary` adapter that scores these files is tracked in the
> [phase 3 epic](https://github.com/autobutler-org/flighthouse/issues/29).

The `flighthouse` CLI itself depends on no Flutter package. Flutter-only helpers live here so that
`dart pub global activate flighthouse` stays Flutter-free.

## Install

```sh
flutter pub add --dev flighthouse_flutter
```

## Write frame timings for flighthouse

`writeTimelineSummary` runs in the driver script, on the host, and writes a `TimelineSummary`'s summary JSON to
`build/flighthouse/timeline/<name>.timeline_summary.json`. `name` is the route or scenario the timeline covers. Set
`FLUTTER_TEST_OUTPUTS_DIR` to move `build`, or pass `directory`.

```dart
import 'package:flighthouse_flutter/flighthouse_flutter.dart';
import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    final timeline = Timeline.fromJson(
      data!['files-scroll'] as Map<String, dynamic>,
    );
    final written = await writeTimelineSummary(
      TimelineSummary.summarize(timeline),
      name: 'files-scroll',
    );
    switch (written) {
      case TimelineSummaryWritten():
        break;
      case TimelineSummaryWriteFailed(:final path, :final reason):
        throw StateError('could not write $path: $reason');
    }
  },
);
```

### On Flutter web

A web build has no VM service, so `traceAction` cannot record a `TimelineSummary`. Measure with
`watchPerformance` instead, naming each scenario by its `reportKey`, and write the reports from the driver with
`writeFrameTimingSummaries`. Each entry of the response data that is a `watchPerformance` report is written to
`build/flighthouse/timeline/<reportKey>.frame_timing_summary.json`. Other entries are listed in `skipped`.

```dart
await binding.watchPerformance(() async {
  await tester.pumpAndSettle();
}, reportKey: 'files-scroll');
```

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
  },
);
```

Point `flighthouse collect` at the same directory in `flighthouse.yaml`:

```yaml
sources:
  timeline:
    dir: build/flighthouse/timeline
```

## License

MIT. See [LICENSE](LICENSE).
