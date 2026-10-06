import '../result/failure.dart';
import '../result/result.dart';
import 'enums.dart';
import 'json_decode.dart';
import 'observations.dart';
import 'report.dart';

final _fingerprintPattern = RegExp(r'^[0-9a-f]{64}$');

String _categoryId(Category category) => category.id;
String _sourceId(Source source) => source.id;

final Decoder<Category> _decodeCategory = enumDecoder(
  Category.values,
  _categoryId,
);
final Decoder<Severity> _decodeSeverity = enumDecoder(
  Severity.values,
  (severity) => severity.id,
);
final Decoder<Source> _decodeSource = enumDecoder(Source.values, _sourceId);
final Decoder<MetricUnit> _decodeUnit = enumDecoder(
  MetricUnit.values,
  (unit) => unit.id,
);

Decoded<String> _decodeFingerprint(Object? json, String path) => switch (json) {
  final String text when _fingerprintPattern.hasMatch(text) => Ok(text),
  _ => mismatch(path, '64 lowercase hex characters', json),
};

Decoded<int> _decodeSchemaVersion(Object? json, String path) => switch (json) {
  currentSchemaVersion => const Ok(currentSchemaVersion),
  _ => mismatch(path, 'schema version $currentSchemaVersion', json),
};

/// Encodes [metric] as JSON.
Map<String, Object?> metricToJson(Metric metric) => {
  'name': metric.name,
  'value': metric.value,
  'unit': metric.unit.id,
};

/// Decodes a [Metric], naming the JSON path of the first problem.
Result<Metric, SchemaFailure> metricFromJson(
  Object? json, [
  String path = rootPath,
]) => readObject(json, path, const ['name', 'value', 'unit']).flatMap(
  (object) => switch ((
    readField(object, 'name', path, decodeNonEmptyString),
    readField(object, 'value', path, decodeNumber),
    readField(object, 'unit', path, _decodeUnit),
  )) {
    (Ok(value: final name), Ok(value: final value), Ok(value: final unit)) =>
      Ok((name: name, value: value, unit: unit)),
    (final name, final value, final unit) => Err(
      firstError([name, value, unit]),
    ),
  },
);

/// Encodes [finding] as JSON.
Map<String, Object?> findingToJson(Finding finding) => {
  'fingerprint': finding.fingerprint,
  'source': finding.source.id,
  'category': finding.category.id,
  'severity': finding.severity.id,
  'rule': finding.rule,
  'route': finding.route,
  'target': finding.target,
  'message': finding.message,
  'metric': switch (finding.metric) {
    final metric? => metricToJson(metric),
    null => null,
  },
};

/// Decodes a [Finding], naming the JSON path of the first problem.
Result<Finding, SchemaFailure> findingFromJson(
  Object? json, [
  String path = rootPath,
]) =>
    readObject(json, path, const [
      'fingerprint',
      'source',
      'category',
      'severity',
      'rule',
      'route',
      'target',
      'message',
      'metric',
    ]).flatMap(
      (object) => switch ((
        readField(object, 'fingerprint', path, _decodeFingerprint),
        readField(object, 'source', path, _decodeSource),
        readField(object, 'category', path, _decodeCategory),
        readField(object, 'severity', path, _decodeSeverity),
        readField(object, 'rule', path, decodeNonEmptyString),
        readField(object, 'route', path, decodeString),
        readField(object, 'target', path, nullable(decodeString)),
        readField(object, 'message', path, decodeString),
        readField(object, 'metric', path, nullable(metricFromJson)),
      )) {
        (
          Ok(value: final fingerprint),
          Ok(value: final source),
          Ok(value: final category),
          Ok(value: final severity),
          Ok(value: final rule),
          Ok(value: final route),
          Ok(value: final target),
          Ok(value: final message),
          Ok(value: final metric),
        ) =>
          Ok((
            fingerprint: fingerprint,
            source: source,
            category: category,
            severity: severity,
            rule: rule,
            route: route,
            target: target,
            message: message,
            metric: metric,
          )),
        (
          final fingerprint,
          final source,
          final category,
          final severity,
          final rule,
          final route,
          final target,
          final message,
          final metric,
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
              message,
              metric,
            ]),
          ),
      },
    );

/// Encodes [outcome] as JSON.
Map<String, Object?> ruleOutcomeToJson(RuleOutcome outcome) => {
  'source': outcome.source.id,
  'category': outcome.category.id,
  'rule': outcome.rule,
  'route': outcome.route,
  'weight': outcome.weight,
  'passed': outcome.passed,
};

/// Decodes a [RuleOutcome], naming the JSON path of the first problem.
Result<RuleOutcome, SchemaFailure> ruleOutcomeFromJson(
  Object? json, [
  String path = rootPath,
]) =>
    readObject(json, path, const [
      'source',
      'category',
      'rule',
      'route',
      'weight',
      'passed',
    ]).flatMap(
      (object) => switch ((
        readField(object, 'source', path, _decodeSource),
        readField(object, 'category', path, _decodeCategory),
        readField(object, 'rule', path, decodeNonEmptyString),
        readField(object, 'route', path, decodeString),
        readField(object, 'weight', path, decodeNonNegative),
        readField(object, 'passed', path, decodeBool),
      )) {
        (
          Ok(value: final source),
          Ok(value: final category),
          Ok(value: final rule),
          Ok(value: final route),
          Ok(value: final weight),
          Ok(value: final passed),
        ) =>
          Ok((
            source: source,
            category: category,
            rule: rule,
            route: route,
            weight: weight,
            passed: passed,
          )),
        (
          final source,
          final category,
          final rule,
          final route,
          final weight,
          final passed,
        ) =>
          Err(firstError([source, category, rule, route, weight, passed])),
      },
    );

/// Encodes [measurement] as JSON.
Map<String, Object?> measurementToJson(Measurement measurement) => {
  'source': measurement.source.id,
  'category': measurement.category.id,
  'route': measurement.route,
  'metric': metricToJson(measurement.metric),
  'weight': measurement.weight,
  'toolScore': measurement.toolScore,
};

/// Decodes a [Measurement], naming the JSON path of the first problem.
Result<Measurement, SchemaFailure> measurementFromJson(
  Object? json, [
  String path = rootPath,
]) =>
    readObject(json, path, const [
      'source',
      'category',
      'route',
      'metric',
      'weight',
      'toolScore',
    ]).flatMap(
      (object) => switch ((
        readField(object, 'source', path, _decodeSource),
        readField(object, 'category', path, _decodeCategory),
        readField(object, 'route', path, decodeString),
        readField(object, 'metric', path, metricFromJson),
        readField(object, 'weight', path, decodeNonNegative),
        readField(object, 'toolScore', path, nullable(decodeUnitInterval)),
      )) {
        (
          Ok(value: final source),
          Ok(value: final category),
          Ok(value: final route),
          Ok(value: final metric),
          Ok(value: final weight),
          Ok(value: final toolScore),
        ) =>
          Ok((
            source: source,
            category: category,
            route: route,
            metric: metric,
            weight: weight,
            toolScore: toolScore,
          )),
        (
          final source,
          final category,
          final route,
          final metric,
          final weight,
          final toolScore,
        ) =>
          Err(firstError([source, category, route, metric, weight, toolScore])),
      },
    );

/// Encodes [metadata] as JSON, with tool versions in [Source] order.
Map<String, Object?> reportMetadataToJson(ReportMetadata metadata) => {
  'app': metadata.app,
  'commit': metadata.commit,
  'timestamp': metadata.timestamp.toIso8601String(),
  'flighthouseVersion': metadata.flighthouseVersion,
  'toolVersions': {
    for (final MapEntry(:key, :value) in metadata.toolVersions.entries)
      key.id: value,
  },
};

/// Decodes [ReportMetadata], naming the JSON path of the first problem.
Result<ReportMetadata, SchemaFailure> reportMetadataFromJson(
  Object? json, [
  String path = rootPath,
]) =>
    readObject(json, path, const [
      'app',
      'commit',
      'timestamp',
      'flighthouseVersion',
      'toolVersions',
    ]).flatMap(
      (object) => switch ((
        readField(object, 'app', path, decodeNonEmptyString),
        readField(object, 'commit', path, nullable(decodeNonEmptyString)),
        readField(object, 'timestamp', path, decodeUtcTimestamp),
        readField(object, 'flighthouseVersion', path, decodeNonEmptyString),
        readField(
          object,
          'toolVersions',
          path,
          keyedDecoder(
            Source.values,
            _sourceId,
            decodeNonEmptyString,
            requireAll: false,
          ),
        ),
      )) {
        (
          Ok(value: final app),
          Ok(value: final commit),
          Ok(value: final timestamp),
          Ok(value: final flighthouseVersion),
          Ok(value: final toolVersions),
        ) =>
          Ok(
            ReportMetadata(
              app: app,
              commit: commit,
              timestamp: timestamp,
              flighthouseVersion: flighthouseVersion,
              toolVersions: toolVersions,
            ),
          ),
        (
          final app,
          final commit,
          final timestamp,
          final flighthouseVersion,
          final toolVersions,
        ) =>
          Err(
            firstError([
              app,
              commit,
              timestamp,
              flighthouseVersion,
              toolVersions,
            ]),
          ),
      },
    );

/// Encodes [scores] as JSON, with every category present in [Category] order.
Map<String, Object?> scoresToJson(Scores scores) => {
  'overall': scores.overall,
  'categories': {
    for (final MapEntry(:key, :value) in scores.categories.entries)
      key.id: value,
  },
};

/// Decodes [Scores], naming the JSON path of the first problem.
Result<Scores, SchemaFailure> scoresFromJson(
  Object? json, [
  String path = rootPath,
]) => readObject(json, path, const ['overall', 'categories']).flatMap(
  (object) => switch ((
    readField(object, 'overall', path, nullable(decodeUnitInterval)),
    readField(
      object,
      'categories',
      path,
      keyedDecoder(Category.values, _categoryId, nullable(decodeUnitInterval)),
    ),
  )) {
    (Ok(value: final overall), Ok(value: final categories)) => Ok(
      Scores(categories: categories, overall: overall),
    ),
    (final overall, final categories) => Err(firstError([overall, categories])),
  },
);

typedef _SortKey = List<Object>;

int _compareKeyPart(Object left, Object right) => switch ((left, right)) {
  (final num left, final num right) => left.compareTo(right),
  (final String left, final String right) => left.compareTo(right),
  _ => throw ArgumentError('sort key parts differ in type: $left, $right'),
};

int _compareKeys(_SortKey left, _SortKey right) => Iterable.generate(
  left.length,
  (index) => _compareKeyPart(left[index], right[index]),
).firstWhere((comparison) => comparison != 0, orElse: () => 0);

_SortKey _ruleOutcomeKey(RuleOutcome outcome) => [
  outcome.source.index,
  outcome.rule,
  outcome.route,
  outcome.category.index,
  outcome.weight,
  outcome.passed ? 1 : 0,
];

_SortKey _measurementKey(Measurement measurement) => [
  measurement.source.index,
  measurement.route,
  measurement.metric.name,
  measurement.category.index,
  measurement.metric.unit.index,
  measurement.metric.value,
  measurement.weight,
  measurement.toolScore ?? -1,
];

_SortKey _findingKey(Finding finding) => [
  finding.fingerprint,
  finding.severity.index,
  finding.message,
];

List<T> _sortedBy<T>(List<T> items, _SortKey Function(T item) keyOf) =>
    [...items]..sort((left, right) => _compareKeys(keyOf(left), keyOf(right)));

/// Encodes [report] as canonical JSON.
///
/// Keys have a fixed order and every list is sorted, so the same report
/// always encodes to the same JSON.
Map<String, Object?> reportToJson(Report report) => {
  'schemaVersion': currentSchemaVersion,
  'metadata': reportMetadataToJson(report.metadata),
  'scores': scoresToJson(report.scores),
  'findings': [
    for (final finding in _sortedBy(report.findings, _findingKey))
      findingToJson(finding),
  ],
  'ruleOutcomes': [
    for (final outcome in _sortedBy(report.ruleOutcomes, _ruleOutcomeKey))
      ruleOutcomeToJson(outcome),
  ],
  'measurements': [
    for (final measurement in _sortedBy(report.measurements, _measurementKey))
      measurementToJson(measurement),
  ],
};

/// Decodes a [Report], naming the JSON path of the first problem.
///
/// A report with a different `schemaVersion` is refused.
Result<Report, SchemaFailure> reportFromJson(
  Object? json, [
  String path = rootPath,
]) =>
    readObject(json, path, const [
      'schemaVersion',
      'metadata',
      'scores',
      'findings',
      'ruleOutcomes',
      'measurements',
    ]).flatMap(
      (object) => switch ((
        readField(object, 'schemaVersion', path, _decodeSchemaVersion),
        readField(object, 'metadata', path, reportMetadataFromJson),
        readField(object, 'scores', path, scoresFromJson),
        readField(object, 'findings', path, listDecoder(findingFromJson)),
        readField(
          object,
          'ruleOutcomes',
          path,
          listDecoder(ruleOutcomeFromJson),
        ),
        readField(
          object,
          'measurements',
          path,
          listDecoder(measurementFromJson),
        ),
      )) {
        (
          Ok(),
          Ok(value: final metadata),
          Ok(value: final scores),
          Ok(value: final findings),
          Ok(value: final ruleOutcomes),
          Ok(value: final measurements),
        ) =>
          Ok(
            Report(
              metadata: metadata,
              scores: scores,
              findings: findings,
              ruleOutcomes: ruleOutcomes,
              measurements: measurements,
            ),
          ),
        (
          final schemaVersion,
          final metadata,
          final scores,
          final findings,
          final ruleOutcomes,
          final measurements,
        ) =>
          Err(
            firstError([
              schemaVersion,
              metadata,
              scores,
              findings,
              ruleOutcomes,
              measurements,
            ]),
          ),
      },
    );
