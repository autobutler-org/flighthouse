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
const _defaultBuildCommand = [
  'flutter',
  'build',
  'web',
  '--release',
  '--dart-define=FLIGHTHOUSE_SEMANTICS=true',
];

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

Parsed<int> _readInteger(
  YamlNode node,
  String keyPath, {
  required int minimum,
  int? maximum,
}) => switch (node) {
  YamlScalar(value: final int value)
      when value >= minimum && (maximum == null || value <= maximum) =>
    Ok(value),
  _ => invalid(
    node,
    keyPath,
    maximum == null
        ? 'expected a positive integer'
        : 'expected an integer from $minimum to $maximum',
  ),
};

Parsed<String> _readApplicationPath(YamlNode node, String keyPath) =>
    readNonEmptyString(node, keyPath).flatMap((value) {
      final uri = Uri.tryParse(value);
      return uri != null &&
              !uri.hasScheme &&
              !uri.hasAuthority &&
              uri.path.startsWith('/')
          ? Ok(value)
          : invalid(
              node,
              keyPath,
              'expected an absolute application path, not an external URL',
            );
    });

Parsed<List<String>> _readCommand(YamlNode node, String keyPath) =>
    listReader(readNonEmptyString)(node, keyPath).flatMap(
      (command) => command.isEmpty
          ? invalid(node, keyPath, 'expected a nonempty command')
          : Ok(command),
    );

Parsed<List<String>> _readWebRoutes(YamlNode node, String keyPath) {
  if (node is! YamlList) {
    return invalid(node, keyPath, 'expected a list');
  }
  final routes = <String>[];
  for (var index = 0; index < node.nodes.length; index++) {
    final routeNode = node.nodes[index];
    switch (_readApplicationPath(routeNode, '$keyPath[$index]')) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        if (routes.contains(value)) {
          return invalid(
            routeNode,
            '$keyPath[$index]',
            'duplicate route $value',
          );
        }
        routes.add(value);
    }
  }
  return routes.isEmpty
      ? invalid(node, keyPath, 'expected at least one route')
      : Ok(List.unmodifiable(routes));
}

Parsed<WebBuildConfig> _readWebBuild(YamlNode node, String keyPath) =>
    readMapping(node, keyPath, const ['command', 'outputDir']).flatMap(
      (mapping) => switch ((
        optionalField(
          mapping,
          'command',
          keyPath,
          _readCommand,
          _defaultBuildCommand,
        ),
        optionalField(
          mapping,
          'outputDir',
          keyPath,
          readNonEmptyString,
          'build/web',
        ),
      )) {
        (Ok(value: final command), Ok(value: final outputDir)) => Ok(
          WebBuildConfig(command: command, outputDir: outputDir),
        ),
        (final command, final outputDir) => Err(
          firstConfigError([command, outputDir]),
        ),
      },
    );

Parsed<WebServeConfig> _readWebServe(YamlNode node, String keyPath) =>
    readMapping(node, keyPath, const ['port']).flatMap(
      (mapping) => optionalField(
        mapping,
        'port',
        keyPath,
        (node, path) => _readInteger(node, path, minimum: 0, maximum: 65535),
        0,
      ).map((port) => WebServeConfig(port: port)),
    );

Parsed<WebReadinessConfig> _readWebReadiness(YamlNode node, String keyPath) =>
    readMapping(node, keyPath, const ['timeoutSeconds', 'selector']).flatMap(
      (mapping) => switch ((
        optionalField(mapping, 'timeoutSeconds', keyPath, readPositive, 30.0),
        optionalField<String?>(
          mapping,
          'selector',
          keyPath,
          readNonEmptyString,
          null,
        ),
      )) {
        (Ok(value: final seconds), Ok(value: final selector)) => Ok(
          WebReadinessConfig(
            timeout: Duration(
              microseconds: (seconds * Duration.microsecondsPerSecond).round(),
            ),
            selector: selector,
          ),
        ),
        (final seconds, final selector) => Err(
          firstConfigError([seconds, selector]),
        ),
      },
    );

Parsed<WebViewportConfig> _readWebViewport(YamlNode node, String keyPath) =>
    readMapping(node, keyPath, const [
      'width',
      'height',
      'deviceScaleFactor',
    ]).flatMap(
      (mapping) => switch ((
        optionalField(
          mapping,
          'width',
          keyPath,
          (node, path) => _readInteger(node, path, minimum: 1),
          1280,
        ),
        optionalField(
          mapping,
          'height',
          keyPath,
          (node, path) => _readInteger(node, path, minimum: 1),
          800,
        ),
        optionalField(mapping, 'deviceScaleFactor', keyPath, readPositive, 1.0),
      )) {
        (
          Ok(value: final width),
          Ok(value: final height),
          Ok(value: final deviceScaleFactor),
        ) =>
          Ok(
            WebViewportConfig(
              width: width,
              height: height,
              deviceScaleFactor: deviceScaleFactor,
            ),
          ),
        (final width, final height, final deviceScaleFactor) => Err(
          firstConfigError([width, height, deviceScaleFactor]),
        ),
      },
    );

Parsed<WebAuthStep> _readWebAuthStep(YamlNode node, String keyPath) =>
    readMapping(
      node,
      keyPath,
      const ['type', 'selector', 'valueFromEnv'],
      required: const ['type'],
    ).flatMap(
      (
        mapping,
      ) => requiredField(mapping, 'type', keyPath, readNonEmptyString).flatMap(
        (type) => switch (type) {
          'type' =>
            readMapping(
              node,
              keyPath,
              const ['type', 'selector', 'valueFromEnv'],
              required: const ['type', 'selector', 'valueFromEnv'],
            ).flatMap(
              (fields) => switch ((
                requiredField(fields, 'selector', keyPath, readNonEmptyString),
                requiredField(
                  fields,
                  'valueFromEnv',
                  keyPath,
                  readNonEmptyString,
                ),
              )) {
                (Ok(value: final selector), Ok(value: final valueFromEnv)) =>
                  Ok(
                    WebTypeAuthStep(
                      selector: selector,
                      valueFromEnv: valueFromEnv,
                    ),
                  ),
                (final selector, final valueFromEnv) => Err(
                  firstConfigError([selector, valueFromEnv]),
                ),
              },
            ),
          'click' || 'wait' =>
            readMapping(
              node,
              keyPath,
              const ['type', 'selector'],
              required: const ['type', 'selector'],
            ).flatMap(
              (fields) =>
                  requiredField(
                    fields,
                    'selector',
                    keyPath,
                    readNonEmptyString,
                  ).map(
                    (selector) => type == 'click'
                        ? WebClickAuthStep(selector: selector)
                        : WebWaitAuthStep(selector: selector),
                  ),
            ),
          _ => invalid(
            mapping['type']!,
            childPath(keyPath, 'type'),
            'expected one of type, click, wait',
          ),
        },
      ),
    );

Parsed<WebAuthConfig> _readWebAuth(YamlNode node, String keyPath) =>
    readMapping(
      node,
      keyPath,
      const ['url', 'steps'],
      required: const ['url', 'steps'],
    ).flatMap(
      (mapping) => switch ((
        requiredField(mapping, 'url', keyPath, _readApplicationPath),
        requiredField(mapping, 'steps', keyPath, listReader(_readWebAuthStep)),
      )) {
        (Ok(), Ok(value: final steps)) when steps.isEmpty => invalid(
          mapping['steps']!,
          childPath(keyPath, 'steps'),
          'expected at least one step',
        ),
        (Ok(value: final url), Ok(value: final steps)) => Ok(
          WebAuthConfig(url: url, steps: steps),
        ),
        (final url, final steps) => Err(firstConfigError([url, steps])),
      },
    );

Parsed<WebLighthouseConfig> _readWebLighthouse(YamlNode node, String keyPath) =>
    readMapping(node, keyPath, const ['command']).flatMap(
      (mapping) => optionalField(
        mapping,
        'command',
        keyPath,
        _readCommand,
        const ['lighthouse'],
      ).map((command) => WebLighthouseConfig(command: command)),
    );

Parsed<WebAxeConfig> _readWebAxe(YamlNode node, String keyPath) =>
    readMapping(node, keyPath, const ['version', 'scriptPath']).flatMap(
      (mapping) => switch ((
        optionalField(
          mapping,
          'version',
          keyPath,
          readNonEmptyString,
          '4.11.1',
        ),
        optionalField<String?>(
          mapping,
          'scriptPath',
          keyPath,
          readNonEmptyString,
          null,
        ),
      )) {
        (Ok(value: final version), Ok(value: final scriptPath)) => Ok(
          WebAxeConfig(version: version, scriptPath: scriptPath),
        ),
        (final version, final scriptPath) => Err(
          firstConfigError([version, scriptPath]),
        ),
      },
    );

Parsed<WebConfig> _readWeb(YamlNode node, String keyPath) =>
    readMapping(node, keyPath, const [
      'projectDir',
      'build',
      'serve',
      'routes',
      'readiness',
      'viewport',
      'auth',
      'lighthouse',
      'axe',
    ]).flatMap(
      (mapping) => switch ((
        optionalField(mapping, 'projectDir', keyPath, readNonEmptyString, '.'),
        optionalField(
          mapping,
          'build',
          keyPath,
          _readWebBuild,
          WebBuildConfig(command: _defaultBuildCommand, outputDir: 'build/web'),
        ),
        optionalField(
          mapping,
          'serve',
          keyPath,
          _readWebServe,
          const WebServeConfig(port: 0),
        ),
        optionalField(
          mapping,
          'routes',
          keyPath,
          _readWebRoutes,
          const <String>[],
        ),
        optionalField(
          mapping,
          'readiness',
          keyPath,
          _readWebReadiness,
          const WebReadinessConfig(
            timeout: Duration(seconds: 30),
            selector: null,
          ),
        ),
        optionalField(
          mapping,
          'viewport',
          keyPath,
          _readWebViewport,
          const WebViewportConfig(
            width: 1280,
            height: 800,
            deviceScaleFactor: 1,
          ),
        ),
        optionalField<WebAuthConfig?>(
          mapping,
          'auth',
          keyPath,
          _readWebAuth,
          null,
        ),
        optionalField(
          mapping,
          'lighthouse',
          keyPath,
          _readWebLighthouse,
          WebLighthouseConfig(command: const ['lighthouse']),
        ),
        optionalField(
          mapping,
          'axe',
          keyPath,
          _readWebAxe,
          const WebAxeConfig(version: '4.11.1', scriptPath: null),
        ),
      )) {
        (
          Ok(),
          Ok(),
          Ok(),
          Ok(value: final routes),
          Ok(),
          Ok(),
          Ok(),
          Ok(),
          Ok(),
        )
            when routes.isEmpty =>
          invalid(
            node,
            childPath(keyPath, 'routes'),
            'expected at least one route',
          ),
        (
          Ok(value: final projectDir),
          Ok(value: final build),
          Ok(value: final serve),
          Ok(value: final routes),
          Ok(value: final readiness),
          Ok(value: final viewport),
          Ok(value: final auth),
          Ok(value: final lighthouse),
          Ok(value: final axe),
        ) =>
          Ok(
            WebConfig(
              projectDir: projectDir,
              build: build,
              serve: serve,
              routes: routes,
              readiness: readiness,
              viewport: viewport,
              auth: auth,
              lighthouse: lighthouse,
              axe: axe,
            ),
          ),
        (
          final projectDir,
          final build,
          final serve,
          final routes,
          final readiness,
          final viewport,
          final auth,
          final lighthouse,
          final axe,
        ) =>
          Err(
            firstConfigError([
              projectDir,
              build,
              serve,
              routes,
              readiness,
              viewport,
              auth,
              lighthouse,
              axe,
            ]),
          ),
      },
    );

YamlNode _sourceKeyNode(Map<String, YamlNode> mapping, Source source) {
  final sourcesNode = mapping['sources'];
  if (sourcesNode is YamlMap) {
    for (final key in sourcesNode.nodes.keys.whereType<YamlNode>()) {
      if (key.value == source.id) return key;
    }
  }
  return sourcesNode!;
}

Parsed<Config> _validatedConfig({
  required Map<String, YamlNode> mapping,
  required String app,
  required String reportDir,
  required String baselinePath,
  required Map<Source, SourceConfig> sources,
  required List<RoutePattern> routePatterns,
  required ScoringConfig scoring,
  required GateConfig gate,
  required WebConfig? web,
}) {
  if (web != null) {
    for (final source in [Source.axe, Source.lighthouse]) {
      if (sources.containsKey(source)) {
        return invalid(
          _sourceKeyNode(mapping, source),
          'sources.${source.id}',
          '${source.id} cannot be imported when web is configured',
        );
      }
    }
  }
  return Ok(
    Config(
      app: app,
      reportDir: reportDir,
      baselinePath: baselinePath,
      sources: sources,
      routePatterns: routePatterns,
      scoring: scoring,
      gate: gate,
      web: web,
    ),
  );
}

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
        'web',
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
        optionalField<WebConfig?>(mapping, 'web', '', _readWeb, null),
      )) {
        (
          Ok(value: final app),
          Ok(value: final reportDir),
          Ok(value: final baselinePath),
          Ok(value: final sources),
          Ok(value: final routePatterns),
          Ok(value: final scoring),
          Ok(value: final gate),
          Ok(value: final web),
        ) =>
          _validatedConfig(
            mapping: mapping,
            app: app,
            reportDir: reportDir,
            baselinePath: baselinePath,
            sources: sources,
            routePatterns: routePatterns,
            scoring: scoring,
            gate: gate,
            web: web,
          ),
        (
          final app,
          final reportDir,
          final baselinePath,
          final sources,
          final routePatterns,
          final scoring,
          final gate,
          final web,
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
              web,
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
