import '../config/config.dart';
import '../model/enums.dart';
import '../model/observations.dart';
import 'diff.dart';

const double _pointTolerance = 1e-9;

/// One reason `flighthouse ci` fails.
sealed class GateViolation {
  /// Base constructor for the violation cases.
  const GateViolation();
}

/// A new finding at or above the gate's minimum severity.
final class NewFindingViolation extends GateViolation {
  /// [finding] is new and severe enough to fail the gate.
  const NewFindingViolation(this.finding);

  /// The new finding.
  final Finding finding;
}

/// A category score dropped by more than its allowed points.
final class CategoryScoreDrop extends GateViolation {
  /// [category] dropped from [baseline] to [current], more than [maxDrop].
  const CategoryScoreDrop({
    required this.category,
    required this.baseline,
    required this.current,
    required this.maxDrop,
  });

  /// The category that dropped.
  final Category category;

  /// The baseline score, from 0 to 1.
  final double baseline;

  /// This run's score, from 0 to 1.
  final double current;

  /// The largest allowed drop, in points.
  final double maxDrop;
}

/// The overall score dropped by more than its allowed points.
final class OverallScoreDrop extends GateViolation {
  /// The overall score dropped from [baseline] to [current], more than
  /// [maxDrop].
  const OverallScoreDrop({
    required this.baseline,
    required this.current,
    required this.maxDrop,
  });

  /// The baseline score, from 0 to 1.
  final double baseline;

  /// This run's score, from 0 to 1.
  final double current;

  /// The largest allowed drop, in points.
  final double maxDrop;
}

/// A category the baseline measured is no longer measured.
///
/// Usually a collector silently stopped producing output.
final class CategoryNoLongerMeasured extends GateViolation {
  /// [category] was measured in the baseline but not in this run.
  const CategoryNoLongerMeasured(this.category);

  /// The category that went missing.
  final Category category;
}

/// The baseline had an overall score and this run has none.
final class OverallNoLongerMeasured extends GateViolation {
  /// Nothing scored in this run, though the baseline had a score.
  const OverallNoLongerMeasured();
}

bool _isSevereEnough(Severity severity, Severity minimum) =>
    severity.index <= minimum.index;

bool _droppedTooFar(double baseline, double current, double maxDrop) =>
    (baseline - current) * 100 > maxDrop + _pointTolerance;

/// Every reason [diff] fails [gate], in a stable order; empty means it passes.
///
/// New findings at or above `minSeverity` fail. A score that drops by more
/// than its allowed points fails. A category or overall score the baseline
/// had but this run lacks fails. Fixed findings and newly measured categories
/// never fail.
List<GateViolation> evaluateGate(
  BaselineDiff diff,
  GateConfig gate,
) => List.unmodifiable(<GateViolation>[
  for (final finding in diff.newFindings)
    if (_isSevereEnough(finding.severity, gate.minSeverity))
      NewFindingViolation(finding),
  for (final MapEntry(key: category, value: change)
      in diff.categoryScores.entries)
    ...switch (change) {
      (baseline: double(), current: null) => [
        CategoryNoLongerMeasured(category),
      ],
      (baseline: final double before, current: final double after)
          when _droppedTooFar(before, after, gate.categoryMaxDrop[category]!) =>
        [
          CategoryScoreDrop(
            category: category,
            baseline: before,
            current: after,
            maxDrop: gate.categoryMaxDrop[category]!,
          ),
        ],
      _ => const <GateViolation>[],
    },
  ...switch (diff.overallScore) {
    (baseline: double(), current: null) => [const OverallNoLongerMeasured()],
    (baseline: final double before, current: final double after)
        when _droppedTooFar(before, after, gate.overallMaxDrop) =>
      [
        OverallScoreDrop(
          baseline: before,
          current: after,
          maxDrop: gate.overallMaxDrop,
        ),
      ],
    _ => const <GateViolation>[],
  },
]);

String _points(double score) => (score * 100).toStringAsFixed(1);

/// Renders [violation] as one line for CI output.
String describeViolation(GateViolation violation) => switch (violation) {
  NewFindingViolation(:final finding) =>
    'new ${finding.severity.id} ${finding.category.id} finding on '
        '${finding.route}: ${finding.rule}: ${finding.message}',
  CategoryScoreDrop(
    :final category,
    :final baseline,
    :final current,
    :final maxDrop,
  ) =>
    '${category.id} score dropped from ${_points(baseline)} to '
        '${_points(current)}, more than the allowed $maxDrop points',
  OverallScoreDrop(:final baseline, :final current, :final maxDrop) =>
    'overall score dropped from ${_points(baseline)} to '
        '${_points(current)}, more than the allowed $maxDrop points',
  CategoryNoLongerMeasured(:final category) =>
    '${category.id} was measured in the baseline but not in this run',
  OverallNoLongerMeasured() =>
    'the baseline had an overall score but nothing was scored in this run',
};
