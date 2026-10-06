import '../model/baseline.dart';
import '../model/observations.dart';
import '../model/report.dart';
import 'fingerprint.dart';

/// The baseline entry for [finding].
BaselineFinding baselineFindingOf(Finding finding) => (
  fingerprint: finding.fingerprint,
  source: finding.source,
  category: finding.category,
  severity: finding.severity,
  rule: finding.rule,
  route: finding.route,
  target: finding.target,
);

/// A baseline accepting every finding and score in [report].
Baseline baselineOf(Report report) => Baseline(
  fingerprintVersion: fingerprintVersion,
  scores: report.scores,
  findings: [for (final finding in report.findings) baselineFindingOf(finding)],
);
