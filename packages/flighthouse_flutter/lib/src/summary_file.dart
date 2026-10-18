import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'timeline_summary_writer.dart';

final RegExp _namePattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

String summaryPath(String name, String suffix, String? directory) {
  if (!_namePattern.hasMatch(name)) {
    throw ArgumentError.value(
      name,
      'name',
      'must start with a letter or digit and contain only letters, digits, '
          '".", "_", and "-"',
    );
  }
  return '${directory ?? '$testOutputsDirectory/flighthouse/timeline'}'
      '/$name.$suffix';
}

Future<TimelineSummaryWrite> writeSummaryJson(
  String path,
  Map<String, dynamic> summaryJson,
) async {
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
