import 'dart:convert';
import 'dart:io';

import 'package:flighthouse/flighthouse.dart';
import 'package:test/test.dart';

const fixtures = 'test/fixtures/attest/1.5.0';

String fixture(String name) => File('$fixtures/$name').readAsStringSync();

Map<String, Object?> fixtureJson(String name) =>
    jsonDecode(fixture(name)) as Map<String, Object?>;

AdapterOutput parsed(String name) =>
    parseAttest((source: Source.attest, path: name, contents: fixture(name)))
        .fold((output) => output, (failure) => fail('$failure'));

String failureOf(Object? json) => parseAttest((
  source: Source.attest,
  path: 'build/a11y/x.json',
  contents: json is String ? json : jsonEncode(json),
)).fold((_) => fail('expected a failure'), describe);

double? a11yScore(AdapterOutput output) => score(
  ruleOutcomes: output.ruleOutcomes,
  measurements: output.measurements,
  scoring: ScoringConfig(weights: defaultCategoryWeights, metrics: const {}),
).categories[Category.a11y];

void main() {
  group('Settings.json', () {
    final output = parsed('Settings.json');

    test('records the tool version and uses the screen as the route', () {
      expect(output.toolVersion, '1.5.0');
      expect(
        {for (final finding in output.findings) finding.route},
        {'Settings'},
      );
    });

    test('keeps every finding with its mapped severity', () {
      expect(
        {for (final finding in output.findings) finding.rule: finding.severity},
        {
          'attest/contrast': Severity.serious,
          'attest/field-label': Severity.serious,
          'attest/image-alt': Severity.serious,
          'attest/interactive-name': Severity.serious,
        },
      );
    });

    test('targets are attest fingerprints, including negative ones', () {
      final targets = {for (final finding in output.findings) finding.target};
      expect(targets, contains('6285b1bfee38b1e3'));
      expect(targets, contains('57308ae3ce70200c'));
    });

    test('messages carry the source location', () {
      final finding = output.findings.singleWhere(
        (finding) => finding.rule == 'attest/interactive-name',
      );
      expect(finding.message, endsWith('(a11y_test.dart:20)'));
      final contrast = output.findings.singleWhere(
        (finding) => finding.rule == 'attest/contrast',
      );
      expect(
        contrast.message,
        'Text contrast is 1.5:1; normal text needs at least 4.5:1.',
      );
    });

    test('records every standard rule, failing exactly the ones found', () {
      expect(output.ruleOutcomes, hasLength(15));
      expect(
        {
          for (final outcome in output.ruleOutcomes)
            if (!outcome.passed) outcome.rule,
        },
        {
          'attest/contrast',
          'attest/field-label',
          'attest/image-alt',
          'attest/interactive-name',
        },
      );
      expect(
        {for (final outcome in output.ruleOutcomes) outcome.category},
        {Category.a11y},
      );
    });

    test('scores as the weighted share of rules that passed', () {
      expect(a11yScore(output), closeTo(49 / 77, 1e-12));
    });

    test('fingerprints are recomputable and unique', () {
      for (final finding in output.findings) {
        expect(
          finding.fingerprint,
          fingerprint(
            source: Source.attest,
            rule: finding.rule,
            route: finding.route,
            target: finding.target,
          ),
        );
      }
      expect({
        for (final finding in output.findings) finding.fingerprint,
      }, hasLength(output.findings.length));
    });
  });

  group('SignIn.json', () {
    final output = parsed('SignIn.json');

    test('a heuristic warning is a moderate finding', () {
      final heading = output.findings.singleWhere(
        (finding) => finding.rule == 'attest/heading-structure',
      );
      expect(heading.severity, Severity.moderate);
      expect(heading.target, '1d8cd040b461f6a7');
      expect(heading.message, endsWith('(a11y_test.dart:12)'));
    });

    test('a negative attest fingerprint is kept as is', () {
      expect(
        output.findings.map((finding) => finding.target),
        contains('-67d6298c587ef6b'),
      );
    });

    test('scores the serious and moderate failures', () {
      expect(a11yScore(output), closeTo(67 / 77, 1e-12));
    });
  });

  test('a rule attest adds later still counts, weighted by its findings', () {
    final json = fixtureJson('SignIn.json');
    final findings = [...json['findings']! as List<Object?>];
    findings.add({
      ...findings.first! as Map<String, Object?>,
      'ruleId': 'attest/future-rule',
      'severity': 'warning',
      'fingerprint': 'abc',
    });
    final output = parseAttest((
      source: Source.attest,
      path: 'x.json',
      contents: jsonEncode({...json, 'findings': findings}),
    )).fold((output) => output, (failure) => fail('$failure'));
    final future = output.ruleOutcomes.singleWhere(
      (outcome) => outcome.rule == 'attest/future-rule',
    );
    expect(future.passed, isFalse);
    expect(future.weight, 3);
  });

  group('failures', () {
    final json = fixtureJson('Settings.json');

    test('invalid JSON', () {
      expect(
        failureOf('{'),
        startsWith('attest: build/a11y/x.json: not valid JSON'),
      );
    });

    test('a missing screen name names the path', () {
      final meta = {...json['meta']! as Map<String, Object?>}
        ..remove('screenName');
      expect(
        failureOf({...json, 'meta': meta}),
        contains(r'$.meta.screenName: expected a value, found nothing'),
      );
    });

    test('an unknown severity lists the known ones', () {
      final findings = [...json['findings']! as List<Object?>];
      findings[0] = {
        ...findings[0]! as Map<String, Object?>,
        'severity': 'fatal',
      };
      expect(
        failureOf({...json, 'findings': findings}),
        contains(
          r'$.findings[0].severity: expected one of error, warning, info, found "fatal"',
        ),
      );
    });

    test('a finding without a fingerprint', () {
      final findings = [...json['findings']! as List<Object?>];
      findings[2] = {...findings[2]! as Map<String, Object?>}
        ..remove('fingerprint');
      expect(
        failureOf({...json, 'findings': findings}),
        contains(r'$.findings[2].fingerprint'),
      );
    });

    test('an untested major version', () {
      final meta = {
        ...json['meta']! as Map<String, Object?>,
        'toolVersion': '2.0.0',
      };
      expect(
        failureOf({...json, 'meta': meta}),
        contains('attest_flutter 2.0.0 is untested; tested majors are 1'),
      );
    });
  });
}
