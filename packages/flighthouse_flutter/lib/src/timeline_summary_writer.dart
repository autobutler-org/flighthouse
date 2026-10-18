import 'package:flutter_driver/flutter_driver.dart';

import 'summary_file.dart';

/// The outcome of [writeTimelineSummary].
sealed class TimelineSummaryWrite {
  /// An outcome for the summary file at [path].
  const TimelineSummaryWrite({required this.path});

  /// The summary file that was written or could not be written.
  final String path;
}

/// The summary JSON was written to [path].
final class TimelineSummaryWritten extends TimelineSummaryWrite {
  /// A summary written to [path].
  const TimelineSummaryWritten({required super.path});
}

/// The summary JSON could not be written to [path] because of [reason].
final class TimelineSummaryWriteFailed extends TimelineSummaryWrite {
  /// A summary not written to [path] because of [reason].
  const TimelineSummaryWriteFailed({required super.path, required this.reason});

  /// Why the summary was not written.
  final String reason;
}

/// Writes the [TimelineSummary.summaryJson] of [summary] where
/// `flighthouse collect` reads timeline summaries.
///
/// The file is `<directory>/<name>.timeline_summary.json`, where [name] is the
/// route or scenario the timeline covers. [name] must start with a letter or
/// digit and contain only letters, digits, `.`, `_`, and `-`; any other name
/// throws an [ArgumentError].
///
/// [directory] defaults to `flighthouse/timeline` under Flutter's
/// [testOutputsDirectory], which is `build/flighthouse/timeline` unless
/// `FLUTTER_TEST_OUTPUTS_DIR` is set. Point `sources.timeline.dir` in
/// `flighthouse.yaml` at the same directory.
///
/// A timeline with no frame events and a file system error are returned as a
/// [TimelineSummaryWriteFailed], never thrown.
Future<TimelineSummaryWrite> writeTimelineSummary(
  TimelineSummary summary, {
  required String name,
  String? directory,
}) async {
  final path = summaryPath(name, 'timeline_summary.json', directory);
  final Map<String, dynamic> summaryJson;
  try {
    summaryJson = summary.summaryJson;
  } on StateError catch (error) {
    return TimelineSummaryWriteFailed(path: path, reason: error.message.trim());
  }
  return writeSummaryJson(path, summaryJson);
}
