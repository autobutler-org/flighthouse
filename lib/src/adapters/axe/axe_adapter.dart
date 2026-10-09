import 'dart:convert';

import '../../model/enums.dart';
import '../../model/json_decode.dart';
import '../../model/observations.dart';
import '../../pipeline/fingerprint.dart';
import '../../result/failure.dart';
import '../../result/result.dart';
import '../adapter.dart';
import '../attest/attest_adapter.dart' show weightOf;

/// The axe-core major versions this adapter was tested against.
const Set<int> testedAxeMajors = {4};

const _impacts = {
  'critical': Severity.critical,
  'serious': Severity.serious,
  'moderate': Severity.moderate,
  'minor': Severity.minor,
};

const _child = ' > ';

final _viewOrdinal = RegExp(r':nth-child\(\d+\)');

final _generatedIdPattern = RegExp(r'#?flt-semantic-node-\d+');

typedef _Node = ({
  Severity? impact,
  String html,
  List<Object> target,
  List<Object>? ancestry,
  String? failureSummary,
});

typedef _Rule = ({String id, Severity? impact, String help, List<_Node> nodes});

typedef _Axe = ({
  String version,
  String route,
  List<_Rule> violations,
  List<_Rule> passes,
  List<_Rule> incomplete,
  List<_Rule> inapplicable,
});

typedef _Observed = ({List<Finding> findings, List<RuleOutcome> outcomes});

bool _isFlutterView(String segment) {
  const name = 'flutter-view';
  if (!segment.startsWith(name)) return false;
  if (segment.length == name.length) return true;
  final next = segment[name.length];
  return next == ':' || next == '.' || next == '[';
}

String _anchorSelector(String selector) {
  final segments = selector.split(_child);
  final index = segments.indexWhere(_isFlutterView);
  if (index < 0) return selector;
  final view = segments[index].replaceFirst(_viewOrdinal, '');
  return [view, ...segments.skip(index + 1)].join(_child);
}

Object _anchorNode(Object? node) => switch (node) {
  final String selector => _anchorSelector(selector),
  final List<Object?> nested => [for (final item in nested) _anchorNode(item)],
  _ => throw ArgumentError('not an axe selector'),
};

bool _isSelectorNode(Object? node) => switch (node) {
  final String text when text.isNotEmpty => true,
  final List<Object?> nested => _isSelectorArray(nested),
  _ => false,
};

bool _isSelectorArray(List<Object?> items) =>
    items.isNotEmpty && items.every(_isSelectorNode);

/// Rewrites an axe target into the stable identity ADR 0024 specifies.
///
/// [target] is the canonical JSON of axe's nested selector array, or null.
/// A path that contains a Flutter view is anchored at `flutter-view`: the
/// document shell and that view's sibling ordinal are dropped, and every
/// descendant ordinal is kept, including the semantics host. Selectors
/// without a Flutter view stay exact. A value that is not that JSON is
/// returned unchanged, so the pipeline can apply this twice.
String? normalizeAxeTarget(String? target) {
  if (target == null) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(target);
  } on FormatException {
    return target;
  }
  if (decoded is! List<Object?> || !_isSelectorArray(decoded)) return target;
  return jsonEncode([for (final item in decoded) _anchorNode(item)]);
}

String? _generatedId(Object node) => switch (node) {
  final String text => _generatedIdPattern.firstMatch(text)?.group(0),
  final List<Object> items => _firstGenerated(items),
  _ => null,
};

String? _firstGenerated(List<Object> items) {
  for (final item in items) {
    if (_generatedId(item) case final id?) return id;
  }
  return null;
}

Decoded<Severity?> _decodeImpact(Object? json, String path) => switch (json) {
  null => const Ok(null),
  final String id when _impacts.containsKey(id) => Ok(_impacts[id]),
  _ => mismatch(
    path,
    'one of critical, serious, moderate, minor, or null',
    json,
  ),
};

Decoded<String> _decodeAxeName(Object? json, String path) =>
    decodeNonEmptyString(json, path).flatMap(
      (name) =>
          name == 'axe-core' ? Ok(name) : mismatch(path, '"axe-core"', json),
    );

Decoded<Object> _decodeSelectorItem(Object? json, String path) =>
    switch (json) {
      final String text when text.isNotEmpty => Ok(text),
      final List<Object?> _ => _decodeTarget(
        json,
        path,
      ).map<Object>((items) => items),
      _ => mismatch(path, 'a non-empty selector string or array', json),
    };

Decoded<List<Object>> _decodeTarget(Object? json, String path) =>
    switch (json) {
      final List<Object?> items when items.isNotEmpty => traverse(
        List<int>.generate(items.length, (index) => index),
        (index) => _decodeSelectorItem(items[index], '$path[$index]'),
      ),
      _ => mismatch(path, 'a non-empty selector array', json),
    };

Decoded<_Node> _nodeFrom({
  required String path,
  required Severity? impact,
  required String html,
  required List<Object> target,
  required List<Object>? ancestry,
  required String? failureSummary,
}) {
  if (ancestry == null) {
    if (_generatedId(target) case final id?) {
      return Err(
        SchemaFailure(
          jsonPath: '$path.target',
          expected: 'output captured with ancestry: true',
          found: 'a generated id ($id) and no ancestry',
        ),
      );
    }
  }
  return Ok((
    impact: impact,
    html: html,
    target: target,
    ancestry: ancestry,
    failureSummary: failureSummary,
  ));
}

Decoded<_Node> _decodeNode(Object? json, String path) =>
    decodeAnyObject(json, path).flatMap(
      (object) => switch ((
        readField(object, 'impact', path, _decodeImpact),
        readField(object, 'html', path, decodeString),
        readField(object, 'target', path, _decodeTarget),
        readOptionalField(object, 'ancestry', path, _decodeTarget),
        readOptionalField(object, 'failureSummary', path, decodeString),
      )) {
        (
          Ok(value: final impact),
          Ok(value: final html),
          Ok(value: final target),
          Ok(value: final ancestry),
          Ok(value: final failureSummary),
        ) =>
          _nodeFrom(
            path: path,
            impact: impact,
            html: html,
            target: target,
            ancestry: ancestry,
            failureSummary: failureSummary,
          ),
        (
          final impact,
          final html,
          final target,
          final ancestry,
          final failureSummary,
        ) =>
          Err(firstError([impact, html, target, ancestry, failureSummary])),
      },
    );

bool _impactsMapped(Severity? impact, List<_Node> nodes) => nodes.isEmpty
    ? impact != null
    : nodes.every((node) => (node.impact ?? impact) != null);

Decoded<_Rule> _decodeRule(
  Object? json,
  String path, {
  required bool requireImpact,
}) => decodeAnyObject(json, path).flatMap(
  (object) => switch ((
    readField(object, 'id', path, decodeNonEmptyString),
    readField(object, 'impact', path, _decodeImpact),
    readField(object, 'help', path, decodeNonEmptyString),
    readField(object, 'nodes', path, listDecoder(_decodeNode)),
  )) {
    (
      Ok(value: final id),
      Ok(value: final impact),
      Ok(value: final help),
      Ok(value: final nodes),
    )
        when !requireImpact || _impactsMapped(impact, nodes) =>
      Ok((id: id, impact: impact, help: help, nodes: nodes)),
    (Ok(), Ok(), Ok(), Ok()) => Err(
      SchemaFailure(
        jsonPath: '$path.impact',
        expected: 'one of critical, serious, moderate, minor',
        found: 'null',
      ),
    ),
    (final id, final impact, final help, final nodes) => Err(
      firstError([id, impact, help, nodes]),
    ),
  },
);

Decoder<List<_Rule>> _rules({required bool requireImpact}) => listDecoder(
  (json, path) => _decodeRule(json, path, requireImpact: requireImpact),
);

Decoded<String> _decodeEngine(Object? json, String path) =>
    decodeAnyObject(json, path).flatMap(
      (object) => switch ((
        readField(object, 'name', path, _decodeAxeName),
        readField(object, 'version', path, decodeNonEmptyString),
      )) {
        (Ok(), Ok(value: final version)) => Ok(version),
        (final name, final version) => Err(firstError([name, version])),
      },
    );

Decoded<_Axe> _decodeAxe(Object? json) =>
    decodeAnyObject(json, rootPath).flatMap(
      (object) => switch ((
        readField(object, 'testEngine', rootPath, _decodeEngine),
        readField(object, 'url', rootPath, decodeNonEmptyString),
        readField(object, 'violations', rootPath, _rules(requireImpact: true)),
        readField(object, 'passes', rootPath, _rules(requireImpact: false)),
        readField(object, 'incomplete', rootPath, _rules(requireImpact: true)),
        readField(
          object,
          'inapplicable',
          rootPath,
          _rules(requireImpact: false),
        ),
      )) {
        (
          Ok(value: final version),
          Ok(value: final route),
          Ok(value: final violations),
          Ok(value: final passes),
          Ok(value: final incomplete),
          Ok(value: final inapplicable),
        ) =>
          Ok((
            version: version,
            route: route,
            violations: violations,
            passes: passes,
            incomplete: incomplete,
            inapplicable: inapplicable,
          )),
        (
          final version,
          final route,
          final violations,
          final passes,
          final incomplete,
          final inapplicable,
        ) =>
          Err(
            firstError([
              version,
              route,
              violations,
              passes,
              incomplete,
              inapplicable,
            ]),
          ),
      },
    );

String _testedMajorList() => (testedAxeMajors.toList()..sort()).join(', ');

int? _majorOf(String version) => int.tryParse(version.split('.').first);

Severity _worst(Iterable<Severity> severities) => severities.reduce(
  (left, right) => left.index <= right.index ? left : right,
);

List<Severity> _impactsOf(_Rule rule) => [
  ?rule.impact,
  for (final node in rule.nodes) ?node.impact,
];

double _weightOf(_Rule rule) {
  final impacts = _impactsOf(rule);
  if (impacts.isEmpty) return weightOf(Severity.minor);
  return weightOf(_worst(impacts));
}

String _canonical(List<Object> selectors) =>
    normalizeAxeTarget(jsonEncode(selectors))!;

String _message({
  required bool needsReview,
  required String help,
  required String? failureSummary,
  required String rawTarget,
  required String html,
}) {
  final headline = needsReview ? 'Needs review: $help' : help;
  final summary = switch (failureSummary) {
    final text? when text.isNotEmpty => '\n$text',
    _ => '',
  };
  return '$headline$summary\n$rawTarget\n$html';
}

Severity _severityOf(_Rule rule, _Node node) =>
    switch ((node.impact, rule.impact)) {
      (final Severity impact, _) => impact,
      (_, final Severity impact) => impact,
      _ => throw ArgumentError('${rule.id} has no impact'),
    };

Finding _findingOf(
  _Rule rule,
  _Node node,
  String route, {
  required bool needsReview,
}) {
  final target = _canonical(node.ancestry ?? node.target);
  return (
    fingerprint: fingerprint(
      source: Source.axe,
      rule: rule.id,
      route: route,
      target: target,
    ),
    source: Source.axe,
    category: Category.a11y,
    severity: _severityOf(rule, node),
    rule: rule.id,
    route: route,
    target: target,
    message: _message(
      needsReview: needsReview,
      help: rule.help,
      failureSummary: node.failureSummary,
      rawTarget: jsonEncode(node.target),
      html: node.html,
    ),
    metric: null,
  );
}

RuleOutcome _outcome(
  _Rule rule,
  String route, {
  required bool passed,
  required double weight,
}) => (
  source: Source.axe,
  category: Category.a11y,
  rule: rule.id,
  route: route,
  weight: weight,
  passed: passed,
);

_Observed _observe(_Axe axe) => (
  findings: [
    for (final rule in axe.violations)
      for (final node in rule.nodes)
        _findingOf(rule, node, axe.route, needsReview: false),
    for (final rule in axe.incomplete)
      for (final node in rule.nodes)
        _findingOf(rule, node, axe.route, needsReview: true),
  ],
  outcomes: [
    for (final rule in axe.violations)
      _outcome(rule, axe.route, passed: false, weight: _weightOf(rule)),
    for (final rule in axe.passes)
      _outcome(rule, axe.route, passed: true, weight: _weightOf(rule)),
    for (final rule in axe.inapplicable)
      _outcome(rule, axe.route, passed: true, weight: weightOf(Severity.info)),
  ],
);

/// Turns axe-core JSON into findings and rule outcomes.
///
/// Violations become one finding per node. Incomplete results are needs-review
/// findings at the same impact, not passes. Passes and inapplicable rules are
/// rule outcomes only. Impact maps onto [Severity] by id, and weights use the
/// shared severity table. The tool version is `testEngine.version`.
///
/// Each finding's target is [normalizeAxeTarget] of `ancestry` when axe
/// captured it, otherwise of `target`. A generated `flt-semantic-node-N` id
/// with no ancestry fails and asks for `ancestry: true`. An untested major
/// version, or a missing or malformed field, fails with the JSON path.
Result<AdapterOutput, Failure> parseAxe(RawArtifact artifact) {
  AdapterFailure failure(String problem) => AdapterFailure(
    tool: Source.axe.id,
    artifactPath: artifact.path,
    problem: problem,
  );
  final Object? json;
  try {
    json = jsonDecode(artifact.contents);
  } on FormatException catch (error) {
    return Err(failure('not valid JSON: ${error.message}'));
  }
  return _decodeAxe(json)
      .mapErr<Failure>((error) => failure(describe(error)))
      .flatMap((axe) {
        if (!_tested(axe.version)) {
          return Err(
            failure(
              'axe-core ${axe.version} is untested; tested majors are '
              '${_testedMajorList()}. Please file an issue.',
            ),
          );
        }
        final observed = _observe(axe);
        return Ok(
          AdapterOutput(
            toolVersion: axe.version,
            findings: observed.findings,
            ruleOutcomes: observed.outcomes,
            measurements: const [],
          ),
        );
      });
}

bool _tested(String version) {
  final major = _majorOf(version);
  return major != null && testedAxeMajors.contains(major);
}
