import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

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

final RegExp _namePattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

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
  if (!_namePattern.hasMatch(name)) {
    throw ArgumentError.value(
      name,
      'name',
      'must start with a letter or digit and contain only letters, digits, '
          '".", "_", and "-"',
    );
  }
  final path =
      '${directory ?? '$testOutputsDirectory/flighthouse/timeline'}'
      '/$name.timeline_summary.json';
  final Map<String, dynamic> summaryJson;
  try {
    summaryJson = summary.summaryJson;
  } on StateError catch (error) {
    return TimelineSummaryWriteFailed(path: path, reason: error.message.trim());
  }
  try {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(json.encode(summaryJson));
    return TimelineSummaryWritten(path: path);
  } on FileSystemException catch (error) {
    return TimelineSummaryWriteFailed(
      path: path,
      reason: error.osError?.message ?? error.message,
    );
  }
}
