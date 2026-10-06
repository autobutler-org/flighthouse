import '../config/config.dart';
import '../model/enums.dart';
import '../model/observations.dart';
import '../model/report.dart';
import 'log_normal.dart';

typedef WeightedScore = ({double weight, double score});

double? weightedMean(Iterable<WeightedScore> items) {
  final totalWeight = items.fold<double>(0, (sum, item) => sum + item.weight);
  return totalWeight == 0
      ? null
      : items.fold<double>(0, (sum, item) => sum + item.weight * item.score) /
            totalWeight;
}

/// The 0 to 1 score of [measurement], or null when it cannot be scored.
///
/// The tool's own score wins. Otherwise the metric is scored on its configured
/// log-normal control points. A metric with neither is reported but not
/// scored.
double? measurementScore(
  Measurement measurement,
  Map<String, ControlPoints> metricControlPoints,
) => switch ((
  measurement.toolScore,
  metricControlPoints[measurement.metric.name],
)) {
  (final toolScore?, _) => toolScore,
  (null, final points?) => logNormalScore(points, measurement.metric.value),
  (null, null) => null,
};

Iterable<WeightedScore> _categoryItems(
  Category category,
  List<RuleOutcome> ruleOutcomes,
  List<Measurement> measurements,
  Map<String, ControlPoints> metricControlPoints,
) => [
  for (final outcome in ruleOutcomes)
    if (outcome.category == category)
      (weight: outcome.weight, score: outcome.passed ? 1.0 : 0.0),
  for (final measurement in measurements)
    if (measurement.category == category)
      if (measurementScore(measurement, metricControlPoints) case final score?)
        (weight: measurement.weight, score: score),
];

/// Scores each category and the overall result.
///
/// A category score is the weighted mean of its rule outcomes (1 if passed,
/// 0 if not) and its scorable measurements. A category with no counted weight
/// is null, meaning not measured. The overall score is the mean of the
/// measured categories weighted by `scoring.weights`, renormalized over the
/// categories that were measured.
Scores score({
  required List<RuleOutcome> ruleOutcomes,
  required List<Measurement> measurements,
  required ScoringConfig scoring,
}) {
  final categories = {
    for (final category in Category.values)
      category: weightedMean(
        _categoryItems(category, ruleOutcomes, measurements, scoring.metrics),
      ),
  };
  return Scores(
    categories: categories,
    overall: weightedMean([
      for (final MapEntry(key: category, value: categoryScore)
          in categories.entries)
        if (categoryScore != null)
          (weight: scoring.weights[category]!, score: categoryScore),
    ]),
  );
}
