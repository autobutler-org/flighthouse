import 'dart:convert';

import 'package:flighthouse/flighthouse.dart';
import 'package:test/test.dart';

import 'samples.dart';

typedef Decode = Result<Object?, SchemaFailure> Function(Object? json);

Object? viaJsonText(Map<String, Object?> json) => jsonDecode(jsonEncode(json));

String pathOf(Result<Object?, SchemaFailure> result) => result.fold(
  (value) => fail('expected a failure, got $value'),
  (failure) => failure.jsonPath,
);

void expectEveryFieldIsChecked(
  String name,
  Map<String, Object?> valid,
  Decode decode,
) {
  group('$name rejects', () {
    test('nothing when valid', () {
      expect(decode(viaJsonText(valid)), isA<Ok<Object?, SchemaFailure>>());
    });

    for (final key in valid.keys) {
      test('a missing $key', () {
        expect(pathOf(decode({...valid}..remove(key))), '\$.$key');
      });

      test('a wrongly typed $key', () {
        expect(
          pathOf(
            decode({
              ...valid,
              key: {'wrong': true},
            }),
          ),
          '\$.$key',
        );
      });
    }

    test('an unknown key', () {
      expect(pathOf(decode({...valid, 'extra': 1})), r'$');
    });

    test('a non-object', () {
      expect(pathOf(decode('text')), r'$');
    });
  });
}

void main() {
  expectEveryFieldIsChecked('metric', metricToJson(frameBuild), metricFromJson);
  expectEveryFieldIsChecked(
    'finding',
    findingToJson(slowFrameFinding),
    findingFromJson,
  );
  expectEveryFieldIsChecked(
    'rule outcome',
    ruleOutcomeToJson(contrastOutcome),
    ruleOutcomeFromJson,
  );
  expectEveryFieldIsChecked(
    'measurement',
    measurementToJson(lcpMeasurement),
    measurementFromJson,
  );
  expectEveryFieldIsChecked(
    'metadata',
    reportMetadataToJson(sampleMetadata()),
    reportMetadataFromJson,
  );
  expectEveryFieldIsChecked(
    'scores',
    scoresToJson(sampleScores()),
    scoresFromJson,
  );
  expectEveryFieldIsChecked(
    'report',
    reportToJson(sampleReport()),
    reportFromJson,
  );

  group('round trip', () {
    test('records decode to equal values', () {
      expect(
        findingFromJson(viaJsonText(findingToJson(contrastFinding))),
        Ok<Finding, SchemaFailure>(contrastFinding),
      );
      expect(
        findingFromJson(viaJsonText(findingToJson(slowFrameFinding))),
        Ok<Finding, SchemaFailure>(slowFrameFinding),
      );
      expect(
        ruleOutcomeFromJson(viaJsonText(ruleOutcomeToJson(labelOutcome))),
        const Ok<RuleOutcome, SchemaFailure>(labelOutcome),
      );
      expect(
        measurementFromJson(viaJsonText(measurementToJson(frameMeasurement))),
        const Ok<Measurement, SchemaFailure>(frameMeasurement),
      );
    });

    test('a report survives encode, JSON text, and decode', () {
      final json = reportToJson(sampleReport());
      final decoded = reportFromJson(viaJsonText(json))
          .fold((report) => report, (failure) => fail('$failure'));
      expect(reportToJson(decoded), json);
    });
  });

  group('canonical encoding', () {
    test('list order does not change the output', () {
      final forward = jsonEncode(reportToJson(sampleReport()));
      final reversed = jsonEncode(
        reportToJson(
          sampleReport(
            findings: [slowFrameFinding, contrastFinding],
            ruleOutcomes: const [labelOutcome, contrastOutcome],
            measurements: const [frameMeasurement, lcpMeasurement],
          ),
        ),
      );
      expect(reversed, forward);
    });

    test('findings are sorted by fingerprint', () {
      final fingerprints = [
        for (final finding
            in reportToJson(sampleReport())['findings']! as List<Object?>)
          (finding! as Map<String, Object?>)['fingerprint'],
      ];
      expect(fingerprints, [...fingerprints]..sort());
    });

    test('every category is present, unmeasured ones as null', () {
      expect(scoresToJson(sampleScores())['categories'], {
        'a11y': 0.82,
        'perf': 0.9,
        'responsiveness': 0.61,
        'memory': null,
        'best-practices': null,
      });
    });

    test('tool versions are written in source order', () {
      final versions =
          reportMetadataToJson(sampleMetadata())['toolVersions']!
              as Map<String, Object?>;
      expect(versions.keys, ['lighthouse', 'axe']);
    });

    test('the timestamp is UTC ISO-8601', () {
      expect(
        reportMetadataToJson(sampleMetadata())['timestamp'],
        '2026-10-06T19:30:00.000Z',
      );
    });
  });

  group('validation', () {
    test('a different schema version is refused', () {
      final json = {...reportToJson(sampleReport()), 'schemaVersion': 2};
      expect(pathOf(reportFromJson(json)), r'$.schemaVersion');
    });

    test('a nested failure names its full path', () {
      final json = reportToJson(sampleReport());
      final findings = [...json['findings']! as List<Object?>];
      findings[1] = {
        ...findings[1]! as Map<String, Object?>,
        'severity': 'high',
      };
      expect(
        pathOf(reportFromJson({...json, 'findings': findings})),
        r'$.findings[1].severity',
      );
    });

    test('a malformed fingerprint is refused', () {
      final json = {...findingToJson(contrastFinding), 'fingerprint': 'ABC'};
      expect(pathOf(findingFromJson(json)), r'$.fingerprint');
    });

    test('a score outside 0 to 1 is refused', () {
      final json = {...scoresToJson(sampleScores()), 'overall': 1.5};
      expect(pathOf(scoresFromJson(json)), r'$.overall');
    });

    test('a missing category score is refused', () {
      final json = scoresToJson(sampleScores());
      final categories = {...json['categories']! as Map<String, Object?>}
        ..remove('memory');
      expect(
        pathOf(scoresFromJson({...json, 'categories': categories})),
        r'$.categories.memory',
      );
    });

    test('a non-UTC timestamp is refused', () {
      final json = {
        ...reportMetadataToJson(sampleMetadata()),
        'timestamp': '2026-10-06T19:30:00+02:00',
      };
      expect(pathOf(reportMetadataFromJson(json)), r'$.timestamp');
    });

    test('a negative measurement weight is refused', () {
      final json = {...measurementToJson(lcpMeasurement), 'weight': -0.5};
      expect(pathOf(measurementFromJson(json)), r'$.weight');
    });

    test('a negative rule weight is refused', () {
      final json = {...ruleOutcomeToJson(labelOutcome), 'weight': -1};
      expect(pathOf(ruleOutcomeFromJson(json)), r'$.weight');
    });
  });

  group('immutability', () {
    test('report lists and maps cannot be changed', () {
      final report = sampleReport();
      expect(
        () => report.findings.add(contrastFinding),
        throwsUnsupportedError,
      );
      expect(report.ruleOutcomes.clear, throwsUnsupportedError);
      expect(report.measurements.clear, throwsUnsupportedError);
      expect(
        () => report.scores.categories[Category.memory] = 1,
        throwsUnsupportedError,
      );
      expect(report.metadata.toolVersions.clear, throwsUnsupportedError);
    });

    test('scores fill in every category', () {
      expect(
        Scores(categories: const {}, overall: null).categories.keys,
        Category.values,
      );
    });
  });
}
