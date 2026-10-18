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
    if (result.writes.length != 2) {
      throw StateError(
        'expected the control and janky summaries, skipped ${result.skipped}',
      );
    }
  },
);
