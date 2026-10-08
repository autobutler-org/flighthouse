import 'dart:convert';
import 'dart:io';

import 'package:flighthouse/flighthouse.dart';
import 'package:flighthouse/src/adapters/lighthouse/lighthouse_adapter.dart';
import 'package:test/test.dart';

const fixtures = 'test/fixtures/lighthouse/13.5.0';

String fixture(String name) => File('$fixtures/$name').readAsStringSync();

Map<String, Object?> fixtureJson(String name) =>
    jsonDecode(fixture(name)) as Map<String, Object?>;

RawArtifact artifactOf(String contents) => (
  source: Source.lighthouse,
  path: 'raw/lighthouse/x.json',
  contents: contents,
);

AdapterOutput parsed(String contents) =>
    parseLighthouse(artifactOf(contents))
        .fold((output) => output, (failure) => fail('$failure'));

String failureOf(Object? json) =>
    parseLighthouse(artifactOf(json is String ? json : jsonEncode(json)))
        .fold((_) => fail('expected a failure'), describe);

Map<Category, double?> scoresOf(AdapterOutput output) => score(
  ruleOutcomes: output.ruleOutcomes,
  measurements: output.measurements,
  scoring: ScoringConfig(weights: defaultCategoryWeights, metrics: const {}),
).categories;

double lhrScore(Map<String, Object?> lhr, String category) =>
    (((lhr['categories']! as Map<String, Object?>)[category]!
                as Map<String, Object?>)['score']!
            as num)
        .toDouble();

Map<String, Object?> withAudit(
  Map<String, Object?> lhr,
  String id,
  Map<String, Object?> changes,
) {
  final audits = {...lhr['audits']! as Map<String, Object?>};
  audits[id] = {...audits[id]! as Map<String, Object?>, ...changes};
  return {...lhr, 'audits': audits};
}

void main() {
  for (final name in ['quark-login.json', 'a11y-failures.json']) {
    group(
      '$name reproduces Lighthouse category scores, which it rounds to 2 places',
      () {
        final lhr = fixtureJson(name);
        final scores = scoresOf(parsed(fixture(name)));
        for (final (id, category) in [
          ('performance', Category.perf),
          ('accessibility', Category.a11y),
          ('best-practices', Category.bestPractices),
        ]) {
          test(id, () {
            expect((scores[category]! * 100).round() / 100, lhrScore(lhr, id));
          });
        }

        test('and ignores the categories it does not model', () {
          expect(scores[Category.memory], isNull);
          expect(scores[Category.responsiveness], isNull);
        });
      },
    );
  }

  group('quark-login.json', () {
    final output = parsed(fixture('quark-login.json'));

    test('records the tool version and the requested route', () {
      expect(output.toolVersion, '13.5.0');
      expect(
        {for (final outcome in output.ruleOutcomes) outcome.route},
        {'http://127.0.0.1:8765/login'},
      );
    });

    test('skips manual, informative, and not-applicable audits', () {
      final rules = {for (final outcome in output.ruleOutcomes) outcome.rule};
      expect(rules, isNot(contains('focus-traps')));
      expect(rules, isNot(contains('image-alt')));
      expect(rules, contains('html-has-lang'));
    });

    test('keeps metric audits as weighted, tool-scored measurements', () {
      final tbt = output.measurements.singleWhere(
        (measurement) => measurement.metric.name == 'total-blocking-time',
      );
      expect(tbt.category, Category.perf);
      expect(tbt.weight, 30);
      expect(tbt.toolScore, 0);
      expect(tbt.metric.unit, MetricUnit.ms);
      final cls = output.measurements.singleWhere(
        (measurement) => measurement.metric.name == 'cumulative-layout-shift',
      );
      expect(cls.metric.unit, MetricUnit.ratio);
    });

    test('a failing weighted metric is a serious finding with its metric', () {
      final finding = output.findings.singleWhere(
        (finding) => finding.rule == 'total-blocking-time',
      );
      expect(finding.severity, Severity.serious);
      expect(finding.metric?.name, 'total-blocking-time');
      expect(finding.target, isNull);
    });

    test('binary failures take their severity from the audit weight', () {
      Severity severityOf(String rule) => output.findings
          .singleWhere((finding) => finding.rule == rule)
          .severity;
      expect(severityOf('deprecations'), Severity.moderate);
      expect(severityOf('errors-in-console'), Severity.minor);
    });
  });

  group('a11y-failures.json', () {
    final output = parsed(fixture('a11y-failures.json'));
    Finding findingFor(String rule) =>
        output.findings.singleWhere((finding) => finding.rule == rule);

    test('makes one finding per failing element, targeted by selector', () {
      expect(findingFor('button-name').target, 'body > button');
      expect(findingFor('image-alt').target, 'body > img');
      expect(findingFor('color-contrast').target, 'body > div');
    });

    test('maps Lighthouse weights back to axe impact', () {
      expect(findingFor('button-name').severity, Severity.critical);
      expect(findingFor('color-contrast').severity, Severity.serious);
      expect(findingFor('landmark-one-main').severity, Severity.moderate);
    });

    test('fingerprints are computed from the finding fields', () {
      for (final finding in output.findings) {
        expect(
          finding.fingerprint,
          fingerprint(
            source: finding.source,
            rule: finding.rule,
            route: finding.route,
            target: finding.target,
          ),
        );
      }
      expect(
        {for (final finding in output.findings) finding.fingerprint}.length,
        output.findings.length,
      );
    });
  });

  group('severity helpers', () {
    test('severityForWeight inverts Lighthouse accessibility weights', () {
      expect(severityForWeight(10), Severity.critical);
      expect(severityForWeight(7), Severity.serious);
      expect(severityForWeight(5), Severity.moderate);
      expect(severityForWeight(3), Severity.moderate);
      expect(severityForWeight(1), Severity.minor);
      expect(severityForWeight(0), Severity.info);
    });

    test('severityForMeasured uses the score band, info when unweighted', () {
      expect(severityForMeasured(30, 0.2), Severity.serious);
      expect(severityForMeasured(30, 0.7), Severity.moderate);
      expect(severityForMeasured(0, 0.2), Severity.info);
    });
  });

  group('failures', () {
    final lhr = fixtureJson('quark-login.json');

    test('invalid JSON', () {
      expect(
        failureOf('{nope'),
        startsWith('lighthouse: raw/lighthouse/x.json: not valid JSON'),
      );
    });

    test('a missing version names the path', () {
      expect(
        failureOf({...lhr}..remove('lighthouseVersion')),
        contains(r'$.lighthouseVersion: expected a value, found nothing'),
      );
    });

    test('an untested major version', () {
      expect(
        failureOf({...lhr, 'lighthouseVersion': '12.8.0'}),
        contains('Lighthouse 12.8.0 is untested; tested majors are 13'),
      );
    });

    test('a runtime error', () {
      expect(
        failureOf({
          ...lhr,
          'runtimeError': {
            'code': 'NO_FCP',
            'message': 'The page did not paint',
          },
        }),
        contains('runtime error: NO_FCP: The page did not paint'),
      );
    });

    test('an unknown score display mode', () {
      expect(
        failureOf(
          withAudit(lhr, 'html-has-lang', {'scoreDisplayMode': 'vibes'}),
        ),
        contains('audit html-has-lang has untested scoreDisplayMode "vibes"'),
      );
    });

    test('an unknown score display mode with a null score', () {
      expect(
        failureOf(
          withAudit(lhr, 'html-has-lang', {
            'scoreDisplayMode': 'vibes',
            'score': null,
          }),
        ),
        contains('audit html-has-lang has untested scoreDisplayMode "vibes"'),
      );
    });

    test('a positively weighted audit error is unusable input', () {
      final failure = failureOf(fixture('audit-errors/weighted-error.json'));
      expect(failure, contains('audit flighthouse-test-audit-error failed'));
      expect(
        failure,
        contains(r'$.audits.flighthouse-test-audit-error.scoreDisplayMode'),
      );
    });

    test('a positively weighted scored audit needs a score', () {
      final failure = failureOf(
        withAudit(lhr, 'html-has-lang', {'score': null}),
      );
      expect(
        failure,
        contains('audit html-has-lang has no score despite a positive weight'),
      );
      expect(failure, contains(r'$.audits.html-has-lang.score'));
    });

    test('an unweighted audit error does not contribute to scoring', () {
      final json = fixtureJson('audit-errors/weighted-error.json');
      final categories = json['categories']! as Map<String, Object?>;
      final category = categories['accessibility']! as Map<String, Object?>;
      final refs = category['auditRefs']! as List<Object?>;
      final ref = refs.cast<Map<String, Object?>>().singleWhere(
        (ref) => ref['id'] == 'flighthouse-test-audit-error',
      );
      ref['weight'] = 0;
      final output = parsed(jsonEncode(json));
      expect(
        output.ruleOutcomes.map((outcome) => outcome.rule),
        isNot(contains('flighthouse-test-audit-error')),
      );
      expect(scoresOf(output)[Category.a11y], isNotNull);
    });

    test('an unknown unit', () {
      expect(
        failureOf(
          withAudit(lhr, 'total-blocking-time', {'numericUnit': 'fortnight'}),
        ),
        contains('untested numericUnit "fortnight"'),
      );
    });

    test('a referenced audit that is missing', () {
      final audits = {...lhr['audits']! as Map<String, Object?>}
        ..remove('html-has-lang');
      expect(
        failureOf({...lhr, 'audits': audits}),
        contains(r'$.audits.html-has-lang: expected a value, found nothing'),
      );
    });

    test('a score outside 0 to 1', () {
      expect(
        failureOf(withAudit(lhr, 'html-has-lang', {'score': 2})),
        contains(r'$.audits.html-has-lang.score'),
      );
    });
  });
}
