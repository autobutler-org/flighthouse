import 'package:flighthouse/flighthouse.dart';
import 'package:flighthouse/src/pipeline/scoring.dart' show weightedMean;
import 'package:test/test.dart';

RuleOutcome rule(
  String id,
  double weight, {
  required bool passed,
  Category category = Category.a11y,
}) => (
  source: Source.axe,
  category: category,
  rule: id,
  route: '/login',
  weight: weight,
  passed: passed,
);

Measurement measured(
  String name,
  double value, {
  double weight = 1,
  double? toolScore,
  Category category = Category.perf,
}) => (
  source: Source.lighthouse,
  category: category,
  route: '/login',
  metric: (name: name, value: value, unit: MetricUnit.ms),
  weight: weight,
  toolScore: toolScore,
);

final defaultScoring = ScoringConfig(
  weights: defaultCategoryWeights,
  metrics: const {},
);

Scores scored({
  List<RuleOutcome> rules = const [],
  List<Measurement> measurements = const [],
  ScoringConfig? scoring,
}) => score(
  ruleOutcomes: rules,
  measurements: measurements,
  scoring: scoring ?? defaultScoring,
);

void main() {
  group('weightedMean', () {
    test('weights each score', () {
      expect(
        weightedMean([(weight: 1, score: 1), (weight: 3, score: 0)]),
        0.25,
      );
    });

    test('is null with no weight', () {
      expect(weightedMean(const []), isNull);
      expect(weightedMean([(weight: 0, score: 1)]), isNull);
    });
  });

  group('measurementScore', () {
    const points = {'frame': (p10: 8.0, median: 16.0)};

    test('uses the tool score first', () {
      expect(
        measurementScore(measured('frame', 100, toolScore: 0.7), points),
        0.7,
      );
    });

    test('falls back to the log-normal curve', () {
      expect(measurementScore(measured('frame', 8), points), 0.9);
      expect(measurementScore(measured('frame', 16), points), 0.5);
    });

    test('is null without a tool score or control points', () {
      expect(measurementScore(measured('heap', 100), points), isNull);
    });
  });

  group('category scores', () {
    test('rules score as the weighted share that passed', () {
      final scores = scored(
        rules: [
          rule('button-name', 10, passed: true),
          rule('color-contrast', 7, passed: false),
          rule('list', 3, passed: true),
        ],
      );
      expect(scores.categories[Category.a11y], closeTo(13 / 20, 1e-12));
    });

    test('rules and measurements share one weighted mean', () {
      final scores = scored(
        rules: [rule('doctype', 1, passed: false, category: Category.perf)],
        measurements: [measured('lcp', 1, weight: 3, toolScore: 0.8)],
      );
      expect(
        scores.categories[Category.perf],
        closeTo((0 * 1 + 0.8 * 3) / 4, 1e-12),
      );
    });

    test('reproduce the Lighthouse formula for weighted metric audits', () {
      final scores = scored(
        measurements: [
          measured('first-contentful-paint', 1, weight: 10, toolScore: 0.8),
          measured('speed-index', 1, weight: 10, toolScore: 0.7),
          measured('largest-contentful-paint', 1, weight: 25, toolScore: 0.92),
          measured('total-blocking-time', 1, weight: 30, toolScore: 0.5),
          measured('cumulative-layout-shift', 1, weight: 25, toolScore: 1),
        ],
      );
      expect(
        scores.categories[Category.perf],
        closeTo(
          (0.8 * 10 + 0.7 * 10 + 0.92 * 25 + 0.5 * 30 + 1 * 25) / 100,
          1e-12,
        ),
      );
    });

    test('unscorable measurements and zero weights do not count', () {
      final scores = scored(
        rules: [
          rule('experimental', 0, passed: false),
          rule('label', 7, passed: true),
        ],
        measurements: [measured('heap', 100, category: Category.a11y)],
      );
      expect(scores.categories[Category.a11y], 1);
    });

    test('a category with no counted weight is not measured', () {
      final scores = scored(
        rules: [rule('experimental', 0, passed: true)],
        measurements: [measured('heap', 100, category: Category.memory)],
      );
      expect(scores.categories[Category.a11y], isNull);
      expect(scores.categories[Category.memory], isNull);
      expect(scores.overall, isNull);
    });

    test('measurements are scored with configured control points', () {
      final scores = scored(
        measurements: [measured('frame', 8, category: Category.responsiveness)],
        scoring: ScoringConfig(
          weights: defaultCategoryWeights,
          metrics: const {'frame': (p10: 8, median: 16)},
        ),
      );
      expect(scores.categories[Category.responsiveness], 0.9);
    });
  });

  group('overall score', () {
    test('renormalizes over measured categories', () {
      final scores = scored(
        rules: [rule('label', 1, passed: false)],
        measurements: [measured('lcp', 1, toolScore: 1)],
      );
      expect(scores.categories[Category.a11y], 0);
      expect(scores.categories[Category.perf], 1);
      expect(scores.overall, closeTo((0 * 0.3 + 1 * 0.3) / 0.6, 1e-12));
    });

    test('ignores measured categories whose weight is 0', () {
      final scores = scored(
        rules: [rule('label', 1, passed: false)],
        measurements: [measured('lcp', 1, toolScore: 1)],
        scoring: ScoringConfig(
          weights: const {Category.perf: 1},
          metrics: const {},
        ),
      );
      expect(scores.overall, 1);
    });

    test('is null when the measured categories all weigh 0', () {
      final scores = scored(
        rules: [rule('label', 1, passed: true)],
        scoring: ScoringConfig(
          weights: const {Category.perf: 1},
          metrics: const {},
        ),
      );
      expect(scores.categories[Category.a11y], 1);
      expect(scores.overall, isNull);
    });

    test('equals the category score when one category is measured', () {
      final scores = scored(
        rules: [rule('a', 3, passed: true), rule('b', 1, passed: false)],
      );
      expect(scores.overall, scores.categories[Category.a11y]);
    });
  });
}
