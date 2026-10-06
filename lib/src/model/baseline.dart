import 'enums.dart';
import 'report.dart';

/// The baseline file schema version this package reads and writes.
const int currentBaselineSchemaVersion = 1;

/// A finding accepted into the baseline.
///
/// Carries the fields that make up its fingerprint plus severity and
/// category, so a baseline change reads clearly in review. The message is
/// left out because it does not identify a finding.
typedef BaselineFinding = ({
  String fingerprint,
  Source source,
  Category category,
  Severity severity,
  String rule,
  String route,
  String? target,
});

/// The committed state that `flighthouse ci` compares a run against.
final class Baseline {
  /// A baseline holding an unmodifiable copy of [findings].
  Baseline({
    required this.fingerprintVersion,
    required this.scores,
    required List<BaselineFinding> findings,
  }) : findings = List.unmodifiable(findings);

  /// The fingerprint scheme the findings were fingerprinted with.
  final String fingerprintVersion;

  /// The accepted category and overall scores.
  final Scores scores;

  /// The accepted findings.
  final List<BaselineFinding> findings;
}
