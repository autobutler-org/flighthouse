import 'package:yaml/yaml.dart';

import '../model/enums.dart';
import '../pipeline/route.dart';
import '../result/failure.dart';
import '../result/result.dart';
import 'config.dart';
import 'yaml_read.dart';

const _defaultReportDir = '.flighthouse';
const _defaultBaselinePath = 'flighthouse-baseline.json';
const _weightTolerance = 1e-9;

String _sourceId(Source source) => source.id;
String _categoryId(Category category) => category.id;

Parsed<SourceConfig> _readSource(YamlNode node, String keyPath) =>
    readMapping(node, keyPath, const ['dir'], required: const ['dir']).flatMap(
      (mapping) => requiredField(
        mapping,
        'dir',
        keyPath,
        readNonEmptyString,
      ).map((dir) => (dir: dir)),
    );

Parsed<RoutePattern> _readRoutePattern(YamlNode node, String keyPath) =>
    readNonEmptyString(node, keyPath).flatMap(
      (pattern) => compileRoutePattern(pattern, keyPath).mapErr(
        (failure) => ConfigFailure(
          keyPath: failure.keyPath,
          problem: failure.problem,
          location: locationOf(node),
        ),
      ),
    );

Parsed<List<RoutePattern>> _readRoutes(YamlNode node, String keyPath) =>
    readMapping(node, keyPath, const ['patterns']).flatMap(
      (mapping) => optionalField(
        mapping,
        'patterns',
        keyPath,
        listReader(_readRoutePattern),
        const <RoutePattern>[],
      ),
    );

Parsed<Map<Category, double>> _readWeights(YamlNode node, String keyPath) =>
    keyedReader(Category.values, _categoryId, readUnitInterval)(
      node,
      keyPath,
    ).flatMap((weights) {
      final sum = weights.values.fold<double>(0, (total, w) => total + w);
      return (sum - 1).abs() <= _weightTolerance
          ? Ok(weights)
          : invalid(node, keyPath, 'weights must sum to 1, but sum to $sum');
    });

Parsed<ControlPoints> _readControlPoints(YamlNode node, String keyPath) =>
    readMapping(
      node,
      keyPath,
      const ['p10', 'median'],
      required: const ['p10', 'median'],
    ).flatMap(
      (mapping) => switch ((
        requiredField(mapping, 'p10', keyPath, readPositive),
        requiredField(mapping, 'median', keyPath, readPositive),
      )) {
        (Ok(value: final p10), Ok(value: final median)) when p10 < median => Ok(
          (p10: p10, median: median),
        ),
        (Ok(value: final p10), Ok(value: final median)) => invalid(
          node,
          keyPath,
          'p10 ($p10) must be less than median ($median)',
        ),
        (final p10, final median) => Err(firstConfigError([p10, median])),
      },
    );

Parsed<ScoringConfig> _readScoring(YamlNode node, String keyPath) =>
    readMapping(node, keyPath, const ['weights', 'metrics']).flatMap(
      (mapping) => switch ((
        optionalField(
          mapping,
          'weights',
          keyPath,
          _readWeights,
          defaultCategoryWeights,
        ),
        optionalField(
          mapping,
          'metrics',
          keyPath,
          openMappingReader(_readControlPoints),
          const <String, ControlPoints>{},
        ),
      )) {
        (Ok(value: final weights), Ok(value: final metrics)) => Ok(
          ScoringConfig(weights: weights, metrics: metrics),
        ),
        (final weights, final metrics) => Err(
          firstConfigError([weights, metrics]),
        ),
      },
    );

typedef _MaxDrops = ({double overall, Map<Category, double> categories});

const _MaxDrops _defaultMaxDrops = (
  overall: defaultOverallMaxDrop,
  categories: defaultCategoryMaxDrop,
);

Parsed<_MaxDrops> _readMaxDrops(YamlNode node, String keyPath) =>
    readMapping(node, keyPath, [
      'overall',
      ...Category.values.map(_categoryId),
    ]).flatMap(
      (mapping) => switch ((
        optionalField(
          mapping,
          'overall',
          keyPath,
          readNonNegative,
          defaultOverallMaxDrop,
        ),
        traverse(
          Category.values,
          (category) => optionalField(
            mapping,
            category.id,
            keyPath,
            readNonNegative,
            defaultCategoryMaxDrop[category]!,
          ).map((drop) => MapEntry(category, drop)),
        ),
      )) {
        (Ok(value: final overall), Ok(value: final drops)) => Ok((
          overall: overall,
          categories: Map.fromEntries(drops),
        )),
        (final overall, final drops) => Err(firstConfigError([overall, drops])),
      },
    );

Parsed<GateConfig> _readGate(YamlNode node, String keyPath) =>
    readMapping(node, keyPath, const ['minSeverity', 'maxScoreDrop']).flatMap(
      (mapping) => switch ((
        optionalField(
          mapping,
          'minSeverity',
          keyPath,
          enumReader(Severity.values, (severity) => severity.id),
          Severity.minor,
        ),
        optionalField(
          mapping,
          'maxScoreDrop',
          keyPath,
          _readMaxDrops,
          _defaultMaxDrops,
        ),
      )) {
        (Ok(value: final minSeverity), Ok(value: final drops)) => Ok(
          GateConfig(
            minSeverity: minSeverity,
            overallMaxDrop: drops.overall,
            categoryMaxDrop: drops.categories,
          ),
        ),
        (final minSeverity, final drops) => Err(
          firstConfigError([minSeverity, drops]),
        ),
      },
    );

Parsed<Config> _readConfig(YamlNode root) =>
    readMapping(
      root,
      '',
      const [
        'app',
        'reportDir',
        'baseline',
        'sources',
        'routes',
        'scoring',
        'gate',
      ],
      required: const ['app'],
    ).flatMap(
      (mapping) => switch ((
        requiredField(mapping, 'app', '', readNonEmptyString),
        optionalField(
          mapping,
          'reportDir',
          '',
          readNonEmptyString,
          _defaultReportDir,
        ),
        optionalField(
          mapping,
          'baseline',
          '',
          readNonEmptyString,
          _defaultBaselinePath,
        ),
        optionalField(
          mapping,
          'sources',
          '',
          keyedReader(Source.values, _sourceId, _readSource),
          const <Source, SourceConfig>{},
        ),
        optionalField(
          mapping,
          'routes',
          '',
          _readRoutes,
          const <RoutePattern>[],
        ),
        optionalField(
          mapping,
          'scoring',
          '',
          _readScoring,
          ScoringConfig(weights: defaultCategoryWeights, metrics: const {}),
        ),
        optionalField(
          mapping,
          'gate',
          '',
          _readGate,
          GateConfig(
            minSeverity: Severity.minor,
            overallMaxDrop: defaultOverallMaxDrop,
            categoryMaxDrop: defaultCategoryMaxDrop,
          ),
        ),
      )) {
        (
          Ok(value: final app),
          Ok(value: final reportDir),
          Ok(value: final baselinePath),
          Ok(value: final sources),
          Ok(value: final routePatterns),
          Ok(value: final scoring),
          Ok(value: final gate),
        ) =>
          Ok(
            Config(
              app: app,
              reportDir: reportDir,
              baselinePath: baselinePath,
              sources: sources,
              routePatterns: routePatterns,
              scoring: scoring,
              gate: gate,
            ),
          ),
        (
          final app,
          final reportDir,
          final baselinePath,
          final sources,
          final routePatterns,
          final scoring,
          final gate,
        ) =>
          Err(
            firstConfigError([
              app,
              reportDir,
              baselinePath,
              sources,
              routePatterns,
              scoring,
              gate,
            ]),
          ),
      },
    );

ConfigFailure _syntaxFailure(YamlException exception) => ConfigFailure(
  keyPath: '(root)',
  problem: 'invalid YAML: ${exception.message}',
  location: switch (exception.span) {
    final span? => (line: span.start.line + 1, column: span.start.column + 1),
    null => null,
  },
);

/// Parses the text of `flighthouse.yaml` into a [Config].
///
/// YAML is a superset of JSON, so a JSON config parses too. Only `app` is
/// required. Unknown keys, wrong types, weights that do not sum to 1, and
/// control points with `p10` not below `median` are failures that name the
/// key and its line and column.
Result<Config, ConfigFailure> parseConfig(String text) {
  final YamlNode root;
  try {
    root = loadYamlNode(text);
  } on YamlException catch (exception) {
    return Err(_syntaxFailure(exception));
  }
  return _readConfig(root);
}
