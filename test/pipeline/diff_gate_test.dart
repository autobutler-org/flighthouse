import 'package:flighthouse/flighthouse.dart';
import 'package:test/test.dart';

import '../model/samples.dart';

Finding findingWith(String seed, Severity severity) => (
  fingerprint: fingerprintOf(seed),
  source: Source.axe,
  category: Category.a11y,
  severity: severity,
  rule: 'rule-$seed',
  route: '/login',
  target: null,
  message: 'message $seed',
  metric: null,
);

Report reportWith({
  List<Finding> findings = const [],
  Map<Category, double?> categories = const {},
  double? overall,
}) => Report(
  metadata: sampleMetadata(),
  scores: Scores(categories: categories, overall: overall),
  findings: findings,
  ruleOutcomes: const [],
  measurements: const [],
);

BaselineDiff diffOf(Report report, Baseline baseline) => diffAgainstBaseline(
  report,
  baseline,
  baselinePath: 'flighthouse-baseline.json',
).fold((diff) => diff, (failure) => fail('$failure'));

GateConfig gateWith({
  Severity minSeverity = Severity.minor,
  double overallMaxDrop = 2,
  Map<Category, double> categoryMaxDrop = defaultCategoryMaxDrop,
}) => GateConfig(
  minSeverity: minSeverity,
  overallMaxDrop: overallMaxDrop,
  categoryMaxDrop: categoryMaxDrop,
);

List<GateViolation> gateOf(
  Report baselineReport,
  Report report, {
  GateConfig? gate,
}) => evaluateGate(
  diffOf(report, baselineOf(baselineReport)),
  gate ?? gateWith(),
);

void main() {
  final kept = findingWith('kept', Severity.serious);
  final fixed = findingWith('fixed', Severity.critical);
  final added = findingWith('added', Severity.moderate);

  group('diffAgainstBaseline', () {
    final diff = diffOf(
      reportWith(findings: [kept, added]),
      baselineOf(reportWith(findings: [kept, fixed])),
    );

    test('splits new, persisting, and fixed findings by fingerprint', () {
      expect(diff.newFindings, [added]);
      expect(diff.persistingFindings, [kept]);
      expect(diff.fixedFindings, [baselineFindingOf(fixed)]);
    });

    test('a reworded message is not a new finding', () {
      final reworded = (
        fingerprint: kept.fingerprint,
        source: kept.source,
        category: kept.category,
        severity: kept.severity,
        rule: kept.rule,
        route: kept.route,
        target: kept.target,
        message: 'a new wording',
        metric: kept.metric,
      );
      final rewordedDiff = diffOf(
        reportWith(findings: [reworded]),
        baselineOf(reportWith(findings: [kept])),
      );
      expect(rewordedDiff.newFindings, isEmpty);
    });

    test('pairs every category score with its baseline', () {
      final scored = diffOf(
        reportWith(categories: {Category.a11y: 0.8}, overall: 0.8),
        baselineOf(
          reportWith(
            categories: {Category.a11y: 0.9, Category.perf: 0.7},
            overall: 0.85,
          ),
        ),
      );
      expect(scored.categoryScores[Category.a11y], (
        baseline: 0.9,
        current: 0.8,
      ));
      expect(scored.categoryScores[Category.perf], (
        baseline: 0.7,
        current: null,
      ));
      expect(scored.categoryScores.keys, Category.values);
      expect(scored.overallScore, (baseline: 0.85, current: 0.8));
    });

    test('refuses a baseline with another fingerprint scheme', () {
      final stale = Baseline(
        fingerprintVersion: 'v1',
        scores: Scores(categories: const {}, overall: null),
        findings: const [],
      );
      final failure = diffAgainstBaseline(
        reportWith(),
        stale,
        baselinePath: 'ci/baseline.json',
      ).fold((_) => fail('expected a failure'), (failure) => failure);
      expect(
        describe(failure),
        'baseline ci/baseline.json: it uses fingerprint scheme v1, this run '
        'uses v2. Run: flighthouse baseline --update',
      );
    });
  });

  group('evaluateGate on findings', () {
    test('passes when nothing is new', () {
      expect(
        gateOf(reportWith(findings: [kept]), reportWith(findings: [kept])),
        isEmpty,
      );
    });

    test('fixed findings never fail', () {
      expect(gateOf(reportWith(findings: [fixed]), reportWith()), isEmpty);
    });

    test('a new finding fails', () {
      final violations = gateOf(reportWith(), reportWith(findings: [added]));
      expect(violations, hasLength(1));
      expect(
        violations.single,
        isA<NewFindingViolation>().having(
          (violation) => violation.finding,
          'finding',
          added,
        ),
      );
    });

    for (final (minimum, failing) in [
      (Severity.critical, [Severity.critical]),
      (Severity.serious, [Severity.critical, Severity.serious]),
      (
        Severity.minor,
        [
          Severity.critical,
          Severity.serious,
          Severity.moderate,
          Severity.minor,
        ],
      ),
      (Severity.info, Severity.values),
    ]) {
      test('minSeverity ${minimum.id} fails exactly $failing', () {
        final findings = [
          for (final severity in Severity.values)
            findingWith(severity.id, severity),
        ];
        final violations = gateOf(
          reportWith(),
          reportWith(findings: findings),
          gate: gateWith(minSeverity: minimum),
        );
        expect(
          violations.whereType<NewFindingViolation>().map(
            (violation) => violation.finding.severity,
          ),
          failing,
        );
      });
    }
  });

  group('evaluateGate on scores', () {
    test('a drop of exactly the allowed points passes', () {
      expect(
        gateOf(
          reportWith(categories: {Category.a11y: 0.90}, overall: 0.90),
          reportWith(categories: {Category.a11y: 0.88}, overall: 0.88),
        ),
        isEmpty,
      );
    });

    test('a drop past the allowed points fails', () {
      final violations = gateOf(
        reportWith(categories: {Category.a11y: 0.90}, overall: 0.90),
        reportWith(categories: {Category.a11y: 0.879}, overall: 0.90),
      );
      expect(violations, hasLength(1));
      final drop = violations.single as CategoryScoreDrop;
      expect(drop.category, Category.a11y);
      expect(drop.maxDrop, 2);
    });

    test('perf allows its own larger drop', () {
      expect(
        gateOf(
          reportWith(categories: {Category.perf: 0.90}),
          reportWith(categories: {Category.perf: 0.86}),
        ),
        isEmpty,
      );
      expect(
        gateOf(
          reportWith(categories: {Category.perf: 0.90}),
          reportWith(categories: {Category.perf: 0.84}),
        ).single,
        isA<CategoryScoreDrop>(),
      );
    });

    test('an overall drop fails on its own threshold', () {
      final violations = gateOf(
        reportWith(overall: 0.9),
        reportWith(overall: 0.85),
      );
      expect(violations.single, isA<OverallScoreDrop>());
    });

    test('an improvement passes', () {
      expect(
        gateOf(
          reportWith(categories: {Category.a11y: 0.5}, overall: 0.5),
          reportWith(categories: {Category.a11y: 0.9}, overall: 0.9),
        ),
        isEmpty,
      );
    });

    test('a category that stopped being measured fails', () {
      final violations = gateOf(
        reportWith(categories: {Category.a11y: 0.9, Category.perf: 0.9}),
        reportWith(categories: {Category.perf: 0.9}),
      );
      expect(
        violations.single,
        isA<CategoryNoLongerMeasured>().having(
          (violation) => violation.category,
          'category',
          Category.a11y,
        ),
      );
    });

    test('an overall score that disappeared fails', () {
      expect(
        gateOf(reportWith(overall: 0.9), reportWith()).single,
        isA<OverallNoLongerMeasured>(),
      );
    });

    test('a newly measured category passes', () {
      expect(
        gateOf(reportWith(), reportWith(categories: {Category.memory: 0.1})),
        isEmpty,
      );
    });
  });

  test('violations come in a stable order', () {
    final violations = gateOf(
      reportWith(
        categories: {Category.a11y: 0.9, Category.perf: 0.9},
        overall: 0.9,
      ),
      reportWith(
        findings: [added],
        categories: {Category.perf: 0.5},
        overall: 0.5,
      ),
    );
    expect(violations.map((violation) => violation.runtimeType), [
      NewFindingViolation,
      CategoryNoLongerMeasured,
      CategoryScoreDrop,
      OverallScoreDrop,
    ]);
    expect(violations.clear, throwsUnsupportedError);
  });

  group('describeViolation', () {
    test('describes each case in one line', () {
      expect(
        describeViolation(NewFindingViolation(added)),
        'new moderate a11y finding on /login: rule-added: message added',
      );
      expect(
        describeViolation(
          const CategoryScoreDrop(
            category: Category.perf,
            baseline: 0.9,
            current: 0.8,
            maxDrop: 5,
          ),
        ),
        'perf score dropped from 90.0 to 80.0, more than the allowed 5.0 points',
      );
      expect(
        describeViolation(
          const OverallScoreDrop(baseline: 0.9, current: 0.8, maxDrop: 2),
        ),
        'overall score dropped from 90.0 to 80.0, more than the allowed 2.0 '
        'points',
      );
      expect(
        describeViolation(const CategoryNoLongerMeasured(Category.memory)),
        'memory was measured in the baseline but not in this run',
      );
      expect(
        describeViolation(const OverallNoLongerMeasured()),
        'the baseline had an overall score but nothing was scored in this run',
      );
    });
  });
}
