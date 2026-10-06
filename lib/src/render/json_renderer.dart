import 'dart:convert';

import '../model/report.dart';
import '../model/report_json.dart';

const _encoder = JsonEncoder.withIndent('  ');

/// Renders [report] as `report.json`: canonical JSON, two-space indented,
/// ending in a newline.
String renderJson(Report report) =>
    '${_encoder.convert(reportToJson(report))}\n';
