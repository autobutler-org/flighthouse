import '../model/baseline.dart';
import '../model/enums.dart';
import '../model/observations.dart';
import '../model/report.dart';
import '../result/failure.dart';
import '../result/result.dart';
import 'fingerprint.dart';

/// A score in the baseline and in this run; null means not measured.
typedef ScoreChange = ({double? baseline, double? current});

/// How a run differs from the committed baseline.
final class BaselineDiff {
  /// A diff holding unmodifiable copies of its collections.
  BaselineDiff({
    required List<Finding> newFindings,
    required List<Finding> persistingFindings,
    required List<BaselineFinding> fixedFindings,
    required Map<Category, ScoreChange> categoryScores,
    required this.overallScore,
  }) : newFindings = List.unmodifiable(newFindings),
       persistingFindings = List.unmodifiable(persistingFindings),
       fixedFindings = List.unmodifiable(fixedFindings),
       categoryScores = Map.unmodifiable(categoryScores);

  /// Findings in this run that are not in the baseline.
  final List<Finding> newFindings;

  /// Findings in this run that are also in the baseline.
  final List<Finding> persistingFindings;

  /// Baseline findings this run no longer has.
  final List<BaselineFinding> fixedFindings;

  /// Each category's score in the baseline and in this run.
  final Map<Category, ScoreChange> categoryScores;

  /// The overall score in the baseline and in this run.
  final ScoreChange overallScore;
}

/// Compares [report] with [baseline] by fingerprint.
///
/// Fails when the baseline was fingerprinted with a different scheme, since
/// every finding would then look new; [baselinePath] names the file in that
/// message.
Result<BaselineDiff, BaselineFailure> diffAgainstBaseline(
  Report report,
  Baseline baseline, {
  required String baselinePath,
}) {
  if (baseline.fingerprintVersion != fingerprintVersion) {
    return Err(
      BaselineFailure(
        path: baselinePath,
        problem:
            'it uses fingerprint scheme ${baseline.fingerprintVersion}, '
            'this run uses $fingerprintVersion',
      ),
    );
  }
  final baselined = {
    for (final finding in baseline.findings) finding.fingerprint,
  };
  final current = {for (final finding in report.findings) finding.fingerprint};
  return Ok(
    BaselineDiff(
      newFindings: [
        for (final finding in report.findings)
          if (!baselined.contains(finding.fingerprint)) finding,
      ],
      persistingFindings: [
        for (final finding in report.findings)
          if (baselined.contains(finding.fingerprint)) finding,
      ],
      fixedFindings: [
        for (final finding in baseline.findings)
          if (!current.contains(finding.fingerprint)) finding,
      ],
      categoryScores: {
        for (final category in Category.values)
          category: (
            baseline: baseline.scores.categories[category],
            current: report.scores.categories[category],
          ),
      },
      overallScore: (
        baseline: baseline.scores.overall,
        current: report.scores.overall,
      ),
    ),
  );
}
