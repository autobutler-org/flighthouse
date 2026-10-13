# Example

Add the package as a dev dependency of the Flutter app that `flighthouse` reports on:

```sh
flutter pub add --dev flighthouse_flutter
```

Record a timeline in an integration test with `traceAction`, keyed by the scenario name:

```dart
await binding.traceAction(
  () async => tester.fling(find.byType(ListView), const Offset(0, -500), 1000),
  reportKey: 'files-scroll',
);
```

Then write its summary from the driver script, `test_driver/perf_driver.dart`:

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

The summary lands in `build/flighthouse/timeline/files-scroll.timeline_summary.json`. Set `sources.timeline.dir`
to `build/flighthouse/timeline` in `flighthouse.yaml` so `flighthouse collect` picks it up.
