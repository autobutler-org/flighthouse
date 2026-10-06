import 'dart:io';

import 'package:flighthouse/flighthouse.dart';
import 'package:test/test.dart';

RoutePattern compiled(String pattern) => compileRoutePattern(
  pattern,
  'routes.patterns[0]',
).fold((value) => value, (failure) => fail('$failure'));

Finding finding({
  String route = 'http://localhost:8080/files/a/b.txt?x=1',
  String rule = 'image-alt',
  String? target = 'body > img',
  Severity severity = Severity.critical,
  String message = 'Images need alt text',
  Source source = Source.lighthouse,
}) => (
  fingerprint: fingerprint(
    source: source,
    rule: rule,
    route: route,
    target: target,
  ),
  source: source,
  category: Category.a11y,
  severity: severity,
  rule: rule,
  route: route,
  target: target,
  message: message,
  metric: null,
);

RuleOutcome outcome({
  String route = '/login',
  double weight = 7,
  bool passed = true,
}) => (
  source: Source.lighthouse,
  category: Category.a11y,
  rule: 'label',
  route: route,
  weight: weight,
  passed: passed,
);

Measurement measurement({String route = '/login'}) => (
  source: Source.lighthouse,
  category: Category.perf,
  route: route,
  metric: (name: 'lcp', value: 1200, unit: MetricUnit.ms),
  weight: 25,
  toolScore: 0.95,
);

Observations observations({
  List<Finding> findings = const [],
  List<RuleOutcome> ruleOutcomes = const [],
  List<Measurement> measurements = const [],
}) => (
  findings: findings,
  ruleOutcomes: ruleOutcomes,
  measurements: measurements,
);

void main() {
  final patterns = [compiled('/files/:path(.*)')];

  group('normalize', () {
    test('rewrites routes everywhere and recomputes fingerprints', () {
      final normalized = normalize(
        observations(
          findings: [finding()],
          ruleOutcomes: [outcome(route: 'http://localhost:8080/files/x')],
          measurements: [measurement(route: '/files/y/')],
        ),
        patterns,
      );
      final only = normalized.findings.single;
      expect(only.route, '/files/:path(.*)');
      expect(
        only.fingerprint,
        fingerprint(
          source: Source.lighthouse,
          rule: 'image-alt',
          route: '/files/:path(.*)',
          target: 'body > img',
        ),
      );
      expect(only.fingerprint, isNot(finding().fingerprint));
      expect(normalized.ruleOutcomes.single.route, '/files/:path(.*)');
      expect(normalized.measurements.single.route, '/files/:path(.*)');
    });

    test('two URLs for one route get one fingerprint', () {
      final normalized = normalize(
        observations(
          findings: [
            finding(route: 'http://127.0.0.1:8765/files/a'),
            finding(route: 'http://localhost:9000/files/b?q=1'),
          ],
        ),
        patterns,
      );
      expect(
        normalized.findings.map((finding) => finding.fingerprint).toSet(),
        hasLength(1),
      );
    });

    test('applies the target normalizer for the finding source only', () {
      final normalized = normalize(
        observations(
          findings: [
            finding(source: Source.axe, target: '#flt-semantic-node-42'),
            finding(source: Source.lighthouse, target: '#flt-semantic-node-42'),
          ],
        ),
        patterns,
        targetNormalizers: {
          Source.axe: (target) => target?.replaceAll(RegExp(r'\d+'), 'N'),
        },
      );
      expect(normalized.findings.map((finding) => finding.target), [
        '#flt-semantic-node-N',
        '#flt-semantic-node-42',
      ]);
    });

    test('keeps everything else about a finding', () {
      final normalized = normalize(
        observations(findings: [finding()]),
        patterns,
      );
      final only = normalized.findings.single;
      expect(only.severity, Severity.critical);
      expect(only.message, 'Images need alt text');
      expect(only.target, 'body > img');
    });

    test('is idempotent', () {
      final once = normalize(
        observations(
          findings: [
            finding(),
            finding(route: '/Login/?x#y'),
          ],
          ruleOutcomes: [outcome(route: 'http://h/files/z')],
        ),
        patterns,
      );
      final twice = normalize(once, patterns);
      expect(twice.findings, once.findings);
      expect(twice.ruleOutcomes, once.ruleOutcomes);
    });
  });

  group('dedupe', () {
    test('keeps the first finding per fingerprint at the highest severity', () {
      final first = finding(severity: Severity.moderate, message: 'first');
      final deduped = dedupe(
        observations(
          findings: [
            first,
            finding(rule: 'label', target: null),
            finding(severity: Severity.critical, message: 'second'),
          ],
        ),
      );
      expect(deduped.findings, hasLength(2));
      expect(deduped.findings.first.message, 'first');
      expect(deduped.findings.first.severity, Severity.critical);
      expect(deduped.findings.last.rule, 'label');
    });

    test('a rule failed anywhere on a route is failed', () {
      final deduped = dedupe(
        observations(
          ruleOutcomes: [
            outcome(passed: true, weight: 3),
            outcome(passed: false, weight: 7),
            outcome(route: '/other'),
          ],
        ),
      );
      expect(deduped.ruleOutcomes, hasLength(2));
      expect(deduped.ruleOutcomes.first.passed, isFalse);
      expect(deduped.ruleOutcomes.first.weight, 7);
      expect(deduped.ruleOutcomes.last.route, '/other');
    });

    test('leaves measurements alone', () {
      final deduped = dedupe(
        observations(measurements: [measurement(), measurement()]),
      );
      expect(deduped.measurements, hasLength(2));
    });

    test('is idempotent and returns unmodifiable lists', () {
      final once = dedupe(
        observations(
          findings: [finding(), finding()],
          ruleOutcomes: [outcome(), outcome(passed: false)],
        ),
      );
      final twice = dedupe(once);
      expect(twice.findings, once.findings);
      expect(twice.ruleOutcomes, once.ruleOutcomes);
      expect(once.findings.clear, throwsUnsupportedError);
    });
  });

  test('a real Lighthouse report normalizes to its requested route', () {
    final contents = File('test/fixtures/lighthouse/13.5.0/quark-login.json')
        .readAsStringSync();
    final output = parseLighthouse((
      source: Source.lighthouse,
      path: 'quark-login.json',
      contents: contents,
    )).fold((output) => output, (failure) => fail('$failure'));
    final normalized = dedupe(
      normalize((
        findings: output.findings,
        ruleOutcomes: output.ruleOutcomes,
        measurements: output.measurements,
      ), const []),
    );
    expect(
      {
        for (final finding in normalized.findings) finding.route,
        for (final outcome in normalized.ruleOutcomes) outcome.route,
        for (final measurement in normalized.measurements) measurement.route,
      },
      {'/login'},
    );
  });
}
