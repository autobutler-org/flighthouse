/// Unified, Lighthouse-style scored reports for Flutter apps.
///
/// The pipeline ingests outputs from attest, Lighthouse, axe, and
/// integration_test, normalizes them to one schema, scores them, diffs them
/// against a baseline, and renders JSON and HTML reports.
library;

export 'src/model/enums.dart';
export 'src/model/observations.dart';
export 'src/model/report.dart';
export 'src/model/report_json.dart';
export 'src/result/failure.dart' hide firstLine;
export 'src/result/result.dart';

/// The version of this package.
const String packageVersion = '0.0.1';
