import 'dart:convert';

import '../../model/enums.dart';
import '../../model/json_decode.dart';
import '../../model/observations.dart';
import '../../pipeline/fingerprint.dart';
import '../../result/failure.dart';
import '../../result/result.dart';
import '../adapter.dart';

/// The attest_flutter major versions this adapter was tested against.
const Set<int> testedAttestMajors = {1};

/// attest's standard rules and the severity of the worst finding each emits,
/// from `RuleEngine.standard()` and the rule sources in attest 1.11.0.
const Map<String, Severity> attestStandardRules = {
  'attest/interactive-name': Severity.serious,
  'attest/image-alt': Severity.serious,
  'attest/placeholder-name': Severity.moderate,
  'attest/field-label': Severity.serious,
  'attest/target-size': Severity.moderate,
  'attest/focus-trap': Severity.serious,
  'attest/ambiguous-name': Severity.moderate,
  'attest/text-overflow': Severity.serious,
  'attest/contrast': Severity.serious,
  'attest/non-text-contrast': Severity.serious,
  'attest/heading-structure': Severity.moderate,
  'attest/focus-order': Severity.moderate,
  'attest/state-exposed': Severity.moderate,
  'attest/adjustable-value': Severity.serious,
  'attest/generic-link-text': Severity.moderate,
};

const Map<String, Severity> _severities = {
  'error': Severity.serious,
  'warning': Severity.moderate,
  'info': Severity.info,
};

double weightOf(Severity severity) => switch (severity) {
  Severity.critical => 10,
  Severity.serious => 7,
  Severity.moderate => 3,
  Severity.minor => 1,
  Severity.info => 0,
};

typedef _AttestFinding = ({
  String ruleId,
  Severity severity,
  String message,
  String fingerprint,
  String? location,
});

typedef _AttestReport = ({
  String screenName,
  String toolVersion,
  List<_AttestFinding> findings,
});

Decoded<Severity> _decodeSeverity(Object? json, String path) =>
    switch (_severities[json]) {
      final severity? => Ok(severity),
      null => mismatch(path, 'one of ${_severities.keys.join(', ')}', json),
    };

String? _locationOf(JsonObject location) =>
    switch ((location['file'], location['line'])) {
      (final String file, final int line) => '${file.split('/').last}:$line',
      _ => null,
    };

Decoded<_AttestFinding> _decodeFinding(Object? json, String path) =>
    decodeAnyObject(json, path).flatMap(
      (object) => switch ((
        readField(object, 'ruleId', path, decodeNonEmptyString),
        readField(object, 'severity', path, _decodeSeverity),
        readField(object, 'message', path, decodeString),
        readField(object, 'fingerprint', path, decodeNonEmptyString),
        readOptionalField(object, 'location', path, decodeAnyObject),
      )) {
        (
          Ok(value: final ruleId),
          Ok(value: final severity),
          Ok(value: final message),
          Ok(value: final fingerprint),
          Ok(value: final location),
        ) =>
          Ok((
            ruleId: ruleId,
            severity: severity,
            message: message,
            fingerprint: fingerprint,
            location: location == null ? null : _locationOf(location),
          )),
        (
          final ruleId,
          final severity,
          final message,
          final fingerprint,
          final location,
        ) =>
          Err(firstError([ruleId, severity, message, fingerprint, location])),
      },
    );

Decoded<({String screenName, String toolVersion})> _decodeMeta(
  Object? json,
  String path,
) => decodeAnyObject(json, path).flatMap(
  (object) => switch ((
    readField(object, 'screenName', path, decodeNonEmptyString),
    readField(object, 'toolVersion', path, decodeNonEmptyString),
  )) {
    (Ok(value: final screenName), Ok(value: final toolVersion)) => Ok((
      screenName: screenName,
      toolVersion: toolVersion,
    )),
    (final screenName, final toolVersion) => Err(
      firstError([screenName, toolVersion]),
    ),
  },
);

Decoded<_AttestReport> _decodeReport(Object? json) =>
    decodeAnyObject(json, rootPath).flatMap(
      (object) => switch ((
        readField(object, 'meta', rootPath, _decodeMeta),
        readField(object, 'findings', rootPath, listDecoder(_decodeFinding)),
      )) {
        (Ok(value: final meta), Ok(value: final findings)) => Ok((
          screenName: meta.screenName,
          toolVersion: meta.toolVersion,
          findings: findings,
        )),
        (final meta, final findings) => Err(firstError([meta, findings])),
      },
    );

Finding _findingOf(_AttestFinding finding, String route) => (
  fingerprint: fingerprint(
    source: Source.attest,
    rule: finding.ruleId,
    route: route,
    target: finding.fingerprint,
  ),
  source: Source.attest,
  category: Category.a11y,
  severity: finding.severity,
  rule: finding.ruleId,
  route: route,
  target: finding.fingerprint,
  message: switch (finding.location) {
    final location? => '${finding.message} ($location)',
    null => finding.message,
  },
  metric: null,
);

Severity _mostSevere(Iterable<Severity> severities) => severities.reduce(
  (left, right) => left.index <= right.index ? left : right,
);

List<RuleOutcome> _outcomesOf(_AttestReport report) {
  final failing = {for (final finding in report.findings) finding.ruleId};
  final rules = {...attestStandardRules.keys, ...failing};
  return [
    for (final rule in rules)
      (
        source: Source.attest,
        category: Category.a11y,
        rule: rule,
        route: report.screenName,
        weight: weightOf(
          failing.contains(rule)
              ? _mostSevere([
                  for (final finding in report.findings)
                    if (finding.ruleId == rule) finding.severity,
                ])
              : attestStandardRules[rule]!,
        ),
        passed: !failing.contains(rule),
      ),
  ];
}

int? _majorOf(String version) => int.tryParse(version.split('.').first);

/// Turns one attest `AuditReport` JSON file into findings and rule outcomes.
///
/// attest writes one report per audited screen; the screen name is the
/// route. Each finding keeps attest's own fingerprint as its target, so it is
/// as stable as attest designed it to be. attest reports only failures, so
/// each of its 15 standard rules with no finding on the screen is recorded as
/// a passed rule outcome; a rule disabled in attest's `RuleConfig` cannot be
/// told apart and counts as passed. Severities map `error` to serious,
/// `warning` to moderate, and `info` to info.
Result<AdapterOutput, Failure> parseAttest(RawArtifact artifact) {
  AdapterFailure failure(String problem) => AdapterFailure(
    tool: Source.attest.id,
    artifactPath: artifact.path,
    problem: problem,
  );
  final Object? json;
  try {
    json = jsonDecode(artifact.contents);
  } on FormatException catch (error) {
    return Err(failure('not valid JSON: ${error.message}'));
  }
  return _decodeReport(json)
      .mapErr<Failure>((error) => failure(describe(error)))
      .flatMap((report) {
        if (!testedAttestMajors.contains(_majorOf(report.toolVersion))) {
          return Err(
            failure(
              'attest_flutter ${report.toolVersion} is untested; tested majors '
              'are ${testedAttestMajors.join(', ')}. Please file an issue.',
            ),
          );
        }
        return Ok(
          AdapterOutput(
            toolVersion: report.toolVersion,
            findings: [
              for (final finding in report.findings)
                _findingOf(finding, report.screenName),
            ],
            ruleOutcomes: _outcomesOf(report),
            measurements: const [],
          ),
        );
      });
}
