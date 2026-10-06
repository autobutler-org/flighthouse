/// Unified, Lighthouse-style scored reports for Flutter apps.
///
/// The pipeline ingests outputs from attest, Lighthouse, axe, and
/// integration_test, normalizes them to one schema, scores them, diffs them
/// against a baseline, and renders JSON and HTML reports.
library;

export 'src/config/config.dart';
export 'src/config/parse_config.dart';
export 'src/model/enums.dart';
export 'src/model/observations.dart';
export 'src/model/report.dart';
export 'src/model/report_json.dart';
export 'src/pipeline/fingerprint.dart' show fingerprint, fingerprintVersion;
export 'src/pipeline/log_normal.dart' show logNormalScore;
export 'src/pipeline/scoring.dart' show measurementScore, score;
export 'src/pipeline/route.dart'
    show RoutePattern, compileRoutePattern, normalizeRoute;
export 'src/result/failure.dart' hide firstLine;
export 'src/result/result.dart';

/// The version of this package.
const String packageVersion = '0.0.1';
