import '../result/failure.dart';
import '../result/result.dart';
import 'baseline.dart';
import 'json_decode.dart';
import 'model_decoders.dart';
import 'report_json.dart';

Decoded<int> _decodeSchemaVersion(Object? json, String path) => switch (json) {
  currentBaselineSchemaVersion => const Ok(currentBaselineSchemaVersion),
  _ => mismatch(
    path,
    'baseline schema version $currentBaselineSchemaVersion',
    json,
  ),
};

Map<String, Object?> _findingToJson(BaselineFinding finding) => {
  'fingerprint': finding.fingerprint,
  'source': finding.source.id,
  'category': finding.category.id,
  'severity': finding.severity.id,
  'rule': finding.rule,
  'route': finding.route,
  'target': finding.target,
};

Decoded<BaselineFinding> _findingFromJson(Object? json, String path) =>
    readObject(json, path, const [
      'fingerprint',
      'source',
      'category',
      'severity',
      'rule',
      'route',
      'target',
    ]).flatMap(
      (object) => switch ((
        readField(object, 'fingerprint', path, decodeFingerprint),
        readField(object, 'source', path, decodeSource),
        readField(object, 'category', path, decodeCategory),
        readField(object, 'severity', path, decodeSeverity),
        readField(object, 'rule', path, decodeNonEmptyString),
        readField(object, 'route', path, decodeString),
        readField(object, 'target', path, nullable(decodeString)),
      )) {
        (
          Ok(value: final fingerprint),
          Ok(value: final source),
          Ok(value: final category),
          Ok(value: final severity),
          Ok(value: final rule),
          Ok(value: final route),
          Ok(value: final target),
        ) =>
          Ok((
            fingerprint: fingerprint,
            source: source,
            category: category,
            severity: severity,
            rule: rule,
            route: route,
            target: target,
          )),
        (
          final fingerprint,
          final source,
          final category,
          final severity,
          final rule,
          final route,
          final target,
        ) =>
          Err(
            firstError([
              fingerprint,
              source,
              category,
              severity,
              rule,
              route,
              target,
            ]),
          ),
      },
    );

int _byFingerprint(BaselineFinding left, BaselineFinding right) =>
    left.fingerprint.compareTo(right.fingerprint);

/// Encodes [baseline] as canonical JSON.
///
/// Findings are sorted by fingerprint and keys have a fixed order, so
/// regenerating an unchanged baseline produces no diff.
Map<String, Object?> baselineToJson(Baseline baseline) => {
  'schemaVersion': currentBaselineSchemaVersion,
  'fingerprintVersion': baseline.fingerprintVersion,
  'scores': scoresToJson(baseline.scores),
  'findings': [
    for (final finding in [...baseline.findings]..sort(_byFingerprint))
      _findingToJson(finding),
  ],
};

/// Decodes a [Baseline], naming the JSON path of the first problem.
///
/// Any fingerprint version is accepted here; comparing a baseline with a run
/// that uses a different one is refused when diffing.
Result<Baseline, SchemaFailure> baselineFromJson(
  Object? json, [
  String path = rootPath,
]) =>
    readObject(json, path, const [
      'schemaVersion',
      'fingerprintVersion',
      'scores',
      'findings',
    ]).flatMap(
      (object) => switch ((
        readField(object, 'schemaVersion', path, _decodeSchemaVersion),
        readField(object, 'fingerprintVersion', path, decodeNonEmptyString),
        readField(object, 'scores', path, scoresFromJson),
        readField(object, 'findings', path, listDecoder(_findingFromJson)),
      )) {
        (
          Ok(),
          Ok(value: final fingerprintVersion),
          Ok(value: final scores),
          Ok(value: final findings),
        ) =>
          Ok(
            Baseline(
              fingerprintVersion: fingerprintVersion,
              scores: scores,
              findings: findings,
            ),
          ),
        (
          final schemaVersion,
          final fingerprintVersion,
          final scores,
          final findings,
        ) =>
          Err(
            firstError([schemaVersion, fingerprintVersion, scores, findings]),
          ),
      },
    );
