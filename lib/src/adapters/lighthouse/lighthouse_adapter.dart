import 'dart:convert';

import '../../model/enums.dart';
import '../../model/json_decode.dart';
import '../../model/observations.dart';
import '../../pipeline/fingerprint.dart';
import '../../result/failure.dart';
import '../../result/result.dart';
import '../adapter.dart';

/// The Lighthouse major versions this adapter was tested against.
const Set<int> testedLighthouseMajors = {13};

const Map<String, Category> _categories = {
  'performance': Category.perf,
  'accessibility': Category.a11y,
  'best-practices': Category.bestPractices,
};

const Map<String, MetricUnit> _units = {
  'millisecond': MetricUnit.ms,
  'byte': MetricUnit.bytes,
  'element': MetricUnit.count,
  'unitless': MetricUnit.ratio,
};

const Set<String> _binaryModes = {'binary'};
const Set<String> _measuredModes = {'numeric', 'metricSavings'};
const Set<String> _unscoredModes = {
  'manual',
  'informative',
  'notApplicable',
  'error',
};

const double _passingScore = 0.9;

typedef _AuditRef = ({String id, double weight});

typedef _Audit = ({
  String id,
  String title,
  double? score,
  String mode,
  double? numericValue,
  String? numericUnit,
  List<String> selectors,
});

typedef _Lhr = ({
  String version,
  String route,
  String? runtimeError,
  Map<Category, List<_AuditRef>> categories,
  Map<String, _Audit> audits,
});

Severity severityForWeight(double weight) => switch (weight) {
  >= 10 => Severity.critical,
  >= 7 => Severity.serious,
  >= 3 => Severity.moderate,
  > 0 => Severity.minor,
  _ => Severity.info,
};

Severity severityForMeasured(double weight, double score) =>
    switch ((weight, score)) {
      (<= 0, _) => Severity.info,
      (_, < 0.5) => Severity.serious,
      _ => Severity.moderate,
    };

Decoded<_AuditRef> _decodeAuditRef(Object? json, String path) =>
    decodeAnyObject(json, path).flatMap(
      (object) => switch ((
        readField(object, 'id', path, decodeNonEmptyString),
        readField(object, 'weight', path, decodeNonNegative),
      )) {
        (Ok(value: final id), Ok(value: final weight)) => Ok((
          id: id,
          weight: weight,
        )),
        (final id, final weight) => Err(firstError([id, weight])),
      },
    );

Decoded<List<_AuditRef>> _decodeCategory(Object? json, String path) =>
    decodeAnyObject(json, path).flatMap(
      (object) =>
          readField(object, 'auditRefs', path, listDecoder(_decodeAuditRef)),
    );

Decoded<List<String>> _decodeSelectors(Object? json, String path) =>
    decodeAnyObject(json, path).flatMap(
      (details) => switch (details['type']) {
        'table' =>
          readField(details, 'items', path, listDecoder(decodeAnyObject)).map(
            (items) => [
              for (final item in items)
                if (item['node'] case {'selector': final String selector})
                  selector,
            ],
          ),
        _ => const Ok(<String>[]),
      },
    );

Decoded<_Audit> _decodeAudit(Object? json, String path) =>
    decodeAnyObject(json, path).flatMap(
      (object) => switch ((
        readField(object, 'id', path, decodeNonEmptyString),
        readField(object, 'title', path, decodeString),
        readField(object, 'score', path, nullable(decodeUnitInterval)),
        readField(object, 'scoreDisplayMode', path, decodeNonEmptyString),
        readOptionalField(object, 'numericValue', path, decodeNumber),
        readOptionalField(object, 'numericUnit', path, decodeNonEmptyString),
        readOptionalField(object, 'details', path, _decodeSelectors),
      )) {
        (
          Ok(value: final id),
          Ok(value: final title),
          Ok(value: final score),
          Ok(value: final mode),
          Ok(value: final numericValue),
          Ok(value: final numericUnit),
          Ok(value: final selectors),
        ) =>
          Ok((
            id: id,
            title: title,
            score: score,
            mode: mode,
            numericValue: numericValue,
            numericUnit: numericUnit,
            selectors: selectors ?? const <String>[],
          )),
        (
          final id,
          final title,
          final score,
          final mode,
          final numericValue,
          final numericUnit,
          final selectors,
        ) =>
          Err(
            firstError([
              id,
              title,
              score,
              mode,
              numericValue,
              numericUnit,
              selectors,
            ]),
          ),
      },
    );

Decoded<String> _decodeRuntimeError(Object? json, String path) =>
    decodeAnyObject(json, path).map(
      (error) => '${error['code'] ?? 'UNKNOWN'}: ${error['message'] ?? ''}',
    );

Decoded<Map<Category, List<_AuditRef>>> _decodeCategories(
  Object? json,
  String path,
) => decodeAnyObject(json, path).flatMap(
  (object) => traverse(
    _categories.entries.where((entry) => object.containsKey(entry.key)),
    (entry) => readField(
      object,
      entry.key,
      path,
      _decodeCategory,
    ).map((refs) => MapEntry(entry.value, refs)),
  ).map(Map.fromEntries),
);

Decoded<Map<String, _Audit>> _decodeAudits(
  Object? json,
  String path,
  Iterable<String> ids,
) => decodeAnyObject(json, path).flatMap(
  (object) => traverse(
    ids.toSet(),
    (id) => readField(
      object,
      id,
      path,
      _decodeAudit,
    ).map((audit) => MapEntry(id, audit)),
  ).map(Map.fromEntries),
);

Decoded<_Lhr> _decodeLhr(
  Object? json,
) => decodeAnyObject(json, rootPath).flatMap(
  (object) => switch ((
    readField(object, 'lighthouseVersion', rootPath, decodeNonEmptyString),
    readOptionalField(object, 'requestedUrl', rootPath, decodeString),
    readField(object, 'finalDisplayedUrl', rootPath, decodeString),
    readOptionalField(object, 'runtimeError', rootPath, _decodeRuntimeError),
    readField(object, 'categories', rootPath, _decodeCategories),
  )) {
    (
      Ok(value: final version),
      Ok(value: final requestedUrl),
      Ok(value: final finalUrl),
      Ok(value: final runtimeError),
      Ok(value: final categories),
    ) =>
      readField(
        object,
        'audits',
        rootPath,
        (json, path) => _decodeAudits(json, path, [
          for (final refs in categories.values)
            for (final ref in refs) ref.id,
        ]),
      ).map(
        (audits) => (
          version: version,
          route: requestedUrl ?? finalUrl,
          runtimeError: runtimeError,
          categories: categories,
          audits: audits,
        ),
      ),
    (
      final version,
      final requestedUrl,
      final finalUrl,
      final runtimeError,
      final categories,
    ) =>
      Err(
        firstError([version, requestedUrl, finalUrl, runtimeError, categories]),
      ),
  },
);

Result<Metric, String> _metricOf(_Audit audit, double score) => switch ((
  audit.numericValue,
  audit.numericUnit,
)) {
  (null, _) => Ok((name: audit.id, value: score, unit: MetricUnit.score)),
  (final double value, final String unit) => switch (_units[unit]) {
    final metricUnit? => Ok((name: audit.id, value: value, unit: metricUnit)),
    null => Err('audit ${audit.id} has untested numericUnit "$unit"'),
  },
  (_, null) => Err('audit ${audit.id} has a numericValue but no numericUnit'),
};

List<Finding> _findingsOf(
  _Audit audit,
  Category category,
  String route,
  Severity severity,
  Metric? metric,
) => [
  for (final target in audit.selectors.isEmpty ? [null] : audit.selectors)
    (
      fingerprint: fingerprint(
        source: Source.lighthouse,
        rule: audit.id,
        route: route,
        target: target,
      ),
      source: Source.lighthouse,
      category: category,
      severity: severity,
      rule: audit.id,
      route: route,
      target: target,
      message: audit.title,
      metric: metric,
    ),
];

typedef _Observed = ({
  List<Finding> findings,
  List<RuleOutcome> ruleOutcomes,
  List<Measurement> measurements,
});

const _Observed _nothing = (findings: [], ruleOutcomes: [], measurements: []);

Result<_Observed, String> _observe(
  _Audit audit,
  _AuditRef ref,
  Category category,
  String route,
) => switch ((audit.mode, audit.score)) {
  (final mode, _) when _unscoredModes.contains(mode) => const Ok(_nothing),
  (_, null) => const Ok(_nothing),
  (final mode, final double score) when _binaryModes.contains(mode) => Ok((
    findings: score >= _passingScore
        ? const []
        : _findingsOf(
            audit,
            category,
            route,
            severityForWeight(ref.weight),
            null,
          ),
    ruleOutcomes: [
      (
        source: Source.lighthouse,
        category: category,
        rule: audit.id,
        route: route,
        weight: ref.weight,
        passed: score >= _passingScore,
      ),
    ],
    measurements: const [],
  )),
  (final mode, final double score) when _measuredModes.contains(mode) =>
    _metricOf(audit, score).map(
      (metric) => (
        findings: score >= _passingScore
            ? const <Finding>[]
            : _findingsOf(
                audit,
                category,
                route,
                severityForMeasured(ref.weight, score),
                metric,
              ),
        ruleOutcomes: const <RuleOutcome>[],
        measurements: [
          (
            source: Source.lighthouse,
            category: category,
            route: route,
            metric: metric,
            weight: ref.weight,
            toolScore: score,
          ),
        ],
      ),
    ),
  (final mode, _) => Err(
    'audit ${audit.id} has untested scoreDisplayMode "$mode"',
  ),
};

int? _majorOf(String version) => int.tryParse(version.split('.').first);

/// Turns a Lighthouse JSON report (LHR) into findings, rule outcomes, and
/// measurements.
///
/// Reads the performance, accessibility, and best-practices categories;
/// others are ignored. Binary audits become rule outcomes, numeric and
/// metric-savings audits become measurements with Lighthouse's own score, and
/// both keep Lighthouse's audit weight, so scoring them reproduces
/// Lighthouse's category scores. An audit scoring below 0.9 is a finding,
/// one per failing element when Lighthouse names elements. The route is the
/// requested URL, falling back to the final one. Reports from an untested
/// major version, reports with a runtime error, and unknown score modes or
/// units are failures rather than best-effort parses.
Result<AdapterOutput, Failure> parseLighthouse(RawArtifact artifact) {
  AdapterFailure failure(String problem) => AdapterFailure(
    tool: Source.lighthouse.id,
    artifactPath: artifact.path,
    problem: problem,
  );
  final Object? json;
  try {
    json = jsonDecode(artifact.contents);
  } on FormatException catch (error) {
    return Err(failure('not valid JSON: ${error.message}'));
  }
  return _decodeLhr(
    json,
  ).mapErr<Failure>((error) => failure(describe(error))).flatMap((lhr) {
    if (!testedLighthouseMajors.contains(_majorOf(lhr.version))) {
      return Err(
        failure(
          'Lighthouse ${lhr.version} is untested; tested majors are '
          '${testedLighthouseMajors.join(', ')}. Please file an issue.',
        ),
      );
    }
    if (lhr.runtimeError case final error?) {
      return Err(failure('Lighthouse reported a runtime error: $error'));
    }
    return traverse(
          [
            for (final MapEntry(key: category, value: refs)
                in lhr.categories.entries)
              for (final ref in refs) (category: category, ref: ref),
          ],
          (entry) => _observe(
            lhr.audits[entry.ref.id]!,
            entry.ref,
            entry.category,
            lhr.route,
          ),
        )
        .mapErr<Failure>(failure)
        .map(
          (observed) => AdapterOutput(
            toolVersion: lhr.version,
            findings: [for (final item in observed) ...item.findings],
            ruleOutcomes: [for (final item in observed) ...item.ruleOutcomes],
            measurements: [for (final item in observed) ...item.measurements],
          ),
        );
  });
}
