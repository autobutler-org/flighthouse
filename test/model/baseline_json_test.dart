import 'dart:convert';

import 'package:flighthouse/flighthouse.dart';
import 'package:test/test.dart';

import 'json_checks.dart';
import 'samples.dart';

void main() {
  final report = sampleReport();
  final baseline = baselineOf(report);

  group('baselineOf', () {
    test('uses the current fingerprint scheme', () {
      expect(baseline.fingerprintVersion, fingerprintVersion);
    });

    test('keeps the report scores', () {
      expect(scoresToJson(baseline.scores), scoresToJson(report.scores));
    });

    test('keeps identity, category, and severity, not the message', () {
      expect(baseline.findings, [
        baselineFindingOf(contrastFinding),
        baselineFindingOf(slowFrameFinding),
      ]);
      expect(baselineFindingOf(contrastFinding), (
        fingerprint: contrastFinding.fingerprint,
        source: Source.axe,
        category: Category.a11y,
        severity: Severity.serious,
        rule: 'color-contrast',
        route: '/login',
        target: 'flt-semantics[role="button"]',
      ));
    });

    test('holds an unmodifiable list', () {
      expect(baseline.findings.clear, throwsUnsupportedError);
    });
  });

  group('baseline JSON', () {
    test('round-trips through JSON text', () {
      final json = baselineToJson(baseline);
      final decoded = baselineFromJson(viaJsonText(json))
          .fold((value) => value, (failure) => fail('$failure'));
      expect(baselineToJson(decoded), json);
    });

    test('regenerating from reordered findings changes nothing', () {
      final reordered = baselineOf(
        sampleReport(findings: [slowFrameFinding, contrastFinding]),
      );
      expect(
        jsonEncode(baselineToJson(reordered)),
        jsonEncode(baselineToJson(baseline)),
      );
    });

    test('a different baseline schema version is refused', () {
      final json = {...baselineToJson(baseline), 'schemaVersion': 2};
      expect(pathOf(baselineFromJson(json)), r'$.schemaVersion');
    });

    test('another fingerprint version still decodes', () {
      final json = {...baselineToJson(baseline), 'fingerprintVersion': 'v0'};
      expect(
        baselineFromJson(json)
            .fold((value) => value.fingerprintVersion, (_) => null),
        'v0',
      );
    });

    test('a bad finding names its index', () {
      final json = baselineToJson(baseline);
      final findings = [...json['findings']! as List<Object?>];
      findings[1] = {
        ...findings[1]! as Map<String, Object?>,
        'fingerprint': 'nope',
      };
      expect(
        pathOf(baselineFromJson({...json, 'findings': findings})),
        r'$.findings[1].fingerprint',
      );
    });
  });

  expectEveryFieldIsChecked(
    'baseline',
    baselineToJson(baseline),
    baselineFromJson,
  );

  final findingJson =
      (baselineToJson(baseline)['findings']! as List<Object?>).first!
          as Map<String, Object?>;
  expectEveryFieldIsChecked(
    'baseline finding',
    findingJson,
    (json) =>
        baselineFromJson({
          ...baselineToJson(baseline),
          'findings': [json],
        }).mapErr(
          (failure) => SchemaFailure(
            jsonPath: failure.jsonPath.replaceFirst(r'$.findings[0]', r'$'),
            expected: failure.expected,
            found: failure.found,
          ),
        ),
  );
}
