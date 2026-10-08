import 'package:flighthouse/flighthouse.dart';
import 'package:test/test.dart';

Config parsed(String text) =>
    parseConfig(text).fold((config) => config, (failure) => fail('$failure'));

ConfigFailure failed(String text) =>
    parseConfig(text)
        .fold((config) => fail('expected a failure'), (failure) => failure);

const fullConfig = '''
app: quark
reportDir: out/flighthouse
baseline: ci/baseline.json
sources:
  attest:
    dir: build/attest
  lighthouse:
    dir: .flighthouse/raw/lighthouse
routes:
  patterns:
    - /files/:path(.*)
    - /users/:tab
scoring:
  weights: {a11y: 0.4, perf: 0.4, responsiveness: 0.2}
  metrics:
    frame_build_time_p90: {p10: 8, median: 16}
gate:
  minSeverity: serious
  maxScoreDrop: {overall: 3, perf: 10}
''';

const webConfig = '''
app: quark
reportDir: output
sources:
  attest:
    dir: build/attest
web:
  projectDir: ../quark
  build:
    command: [flutter, build, web, --release, --dart-define=FLIGHTHOUSE_SEMANTICS=true]
    outputDir: dist/web
  serve:
    port: 4321
  routes: [/files, /photos?album=recent#top]
  readiness:
    timeoutSeconds: 12.5
    selector: '[role="main"]'
  viewport:
    width: 1440
    height: 900
    deviceScaleFactor: 2
  auth:
    url: /login
    steps:
      - type: type
        selector: 'input[aria-label="Username"]'
        valueFromEnv: FLIGHTHOUSE_USERNAME
      - type: click
        selector: '[aria-label="Sign in"]'
      - type: wait
        selector: '[role="main"]'
  lighthouse:
    command: [npx, lighthouse]
  axe:
    version: 4.11.1
    scriptPath: tools/axe.min.js
''';

void main() {
  group('a minimal config', () {
    final config = parsed('app: quark\n');

    test('needs only the app name', () {
      expect(config.app, 'quark');
    });

    test('gets the documented defaults', () {
      expect(config.reportDir, '.flighthouse');
      expect(config.baselinePath, 'flighthouse-baseline.json');
      expect(config.sources, isEmpty);
      expect(config.routePatterns, isEmpty);
      expect(config.scoring.weights, defaultCategoryWeights);
      expect(config.scoring.metrics, isEmpty);
      expect(config.gate.minSeverity, Severity.minor);
      expect(config.gate.overallMaxDrop, 2);
      expect(config.gate.categoryMaxDrop, defaultCategoryMaxDrop);
      expect(config.web, isNull);
      expect(config.auditSources, isEmpty);
    });

    test('treats empty sections as absent', () {
      final empty = parsed('app: quark\nsources:\nroutes:\nscoring:\ngate:\n');
      expect(empty.sources, isEmpty);
      expect(empty.scoring.weights, defaultCategoryWeights);
      expect(empty.gate.minSeverity, Severity.minor);
    });
  });

  group('web config', () {
    final config = parsed(webConfig);
    final web = config.web!;

    test('reads every value', () {
      expect(web.projectDir, '../quark');
      expect(web.build.command, [
        'flutter',
        'build',
        'web',
        '--release',
        '--dart-define=FLIGHTHOUSE_SEMANTICS=true',
      ]);
      expect(web.build.outputDir, 'dist/web');
      expect(web.serve.port, 4321);
      expect(web.routes, ['/files', '/photos?album=recent#top']);
      expect(web.readiness.timeout, const Duration(milliseconds: 12500));
      expect(web.readiness.selector, '[role="main"]');
      expect(web.viewport.width, 1440);
      expect(web.viewport.height, 900);
      expect(web.viewport.deviceScaleFactor, 2);
      expect(web.auth?.url, '/login');
      expect(web.auth?.steps, [
        isA<WebTypeAuthStep>()
            .having((step) => step.selector, 'selector', contains('Username'))
            .having(
              (step) => step.valueFromEnv,
              'valueFromEnv',
              'FLIGHTHOUSE_USERNAME',
            ),
        isA<WebClickAuthStep>().having(
          (step) => step.selector,
          'selector',
          '[aria-label="Sign in"]',
        ),
        isA<WebWaitAuthStep>().having(
          (step) => step.selector,
          'selector',
          '[role="main"]',
        ),
      ]);
      expect(web.lighthouse.command, ['npx', 'lighthouse']);
      expect(web.axe.version, '4.11.1');
      expect(web.axe.scriptPath, 'tools/axe.min.js');
    });

    test('adds generated sources without changing imported sources', () {
      expect(config.sources, {Source.attest: (dir: 'build/attest')});
      expect(config.auditSources, {
        Source.attest,
        Source.lighthouse,
        Source.axe,
      });
    });

    test('copies collections', () {
      expect(web.build.command.clear, throwsUnsupportedError);
      expect(web.routes.clear, throwsUnsupportedError);
      expect(web.auth!.steps.clear, throwsUnsupportedError);
      expect(web.lighthouse.command.clear, throwsUnsupportedError);
      expect(config.auditSources.clear, throwsUnsupportedError);
    });

    test('uses the documented defaults', () {
      final defaults = parsed('app: quark\nweb:\n  routes: [/login]\n').web!;
      expect(defaults.projectDir, '.');
      expect(defaults.build.command, [
        'flutter',
        'build',
        'web',
        '--release',
        '--dart-define=FLIGHTHOUSE_SEMANTICS=true',
      ]);
      expect(defaults.build.outputDir, 'build/web');
      expect(defaults.serve.port, 0);
      expect(defaults.readiness.timeout, const Duration(seconds: 30));
      expect(defaults.readiness.selector, isNull);
      expect(defaults.viewport.width, 1280);
      expect(defaults.viewport.height, 800);
      expect(defaults.viewport.deviceScaleFactor, 1);
      expect(defaults.auth, isNull);
      expect(defaults.lighthouse.command, ['lighthouse']);
      expect(defaults.axe.version, '4.11.1');
      expect(defaults.axe.scriptPath, isNull);
    });
  });

  group('a full config', () {
    final config = parsed(fullConfig);

    test('reads paths and sources', () {
      expect(config.reportDir, 'out/flighthouse');
      expect(config.baselinePath, 'ci/baseline.json');
      expect(config.sources, {
        Source.attest: (dir: 'build/attest'),
        Source.lighthouse: (dir: '.flighthouse/raw/lighthouse'),
      });
    });

    test('compiles route patterns in order', () {
      expect(config.routePatterns.map((pattern) => pattern.pattern), [
        '/files/:path(.*)',
        '/users/:tab',
      ]);
      expect(
        normalizeRoute('/files/a/b', config.routePatterns),
        '/files/:path(.*)',
      );
    });

    test('gives unlisted categories a weight of 0', () {
      expect(config.scoring.weights, {
        Category.a11y: 0.4,
        Category.perf: 0.4,
        Category.responsiveness: 0.2,
        Category.memory: 0.0,
        Category.bestPractices: 0.0,
      });
    });

    test('reads metric control points', () {
      expect(config.scoring.metrics, {
        'frame_build_time_p90': (p10: 8.0, median: 16.0),
      });
    });

    test('overrides only the gate thresholds given', () {
      expect(config.gate.minSeverity, Severity.serious);
      expect(config.gate.overallMaxDrop, 3);
      expect(config.gate.categoryMaxDrop[Category.perf], 10);
      expect(config.gate.categoryMaxDrop[Category.a11y], 2);
    });

    test('is unmodifiable', () {
      expect(config.sources.clear, throwsUnsupportedError);
      expect(config.routePatterns.clear, throwsUnsupportedError);
      expect(config.scoring.weights.clear, throwsUnsupportedError);
      expect(config.scoring.metrics.clear, throwsUnsupportedError);
      expect(config.gate.categoryMaxDrop.clear, throwsUnsupportedError);
    });
  });

  test('JSON is accepted', () {
    final config = parsed(
      '{"app": "quark", "gate": {"minSeverity": "critical"}}',
    );
    expect(config.gate.minSeverity, Severity.critical);
  });

  group('failures name the key and where it is', () {
    void expectFailure(
      String text,
      String keyPath, {
      int? line,
      int? column,
      String? problem,
    }) {
      final failure = failed(text);
      expect(failure.keyPath, keyPath);
      if (line != null) {
        expect(failure.location?.line, line);
      }
      if (column != null) {
        expect(failure.location?.column, column);
      }
      if (problem != null) {
        expect(failure.problem, contains(problem));
      }
    }

    test('an empty file needs an app', () {
      expectFailure('', 'app', problem: 'is required');
    });

    test('a missing app', () {
      expectFailure('reportDir: out\n', 'app', line: 1, problem: 'is required');
    });

    test('a root that is not a mapping', () {
      expectFailure('- app\n', '(root)', problem: 'expected a mapping');
    });

    test('an unknown top-level key', () {
      expectFailure('app: quark\napps: x\n', 'apps', line: 2, column: 1);
    });

    test('an unknown nested key, with its column', () {
      expectFailure(
        'app: quark\ngate:\n  minSeverty: minor\n',
        'gate.minSeverty',
        line: 3,
        column: 3,
        problem: 'unknown key; expected one of minSeverity, maxScoreDrop',
      );
    });

    test('a blank app name', () {
      expectFailure('app: "  "\n', 'app', problem: 'non-empty string');
    });

    test('a wrongly typed path', () {
      expectFailure('app: quark\nreportDir: 3\n', 'reportDir', line: 2);
    });

    test('an unknown source', () {
      expectFailure(
        'app: quark\nsources:\n  eslint: {dir: x}\n',
        'sources.eslint',
        line: 3,
      );
    });

    for (final source in ['axe', 'lighthouse']) {
      test('web rejects an imported $source source', () {
        expectFailure(
          'app: quark\nsources:\n  $source: {dir: imported}\nweb:\n  routes: [/login]\n',
          'sources.$source',
          problem: 'cannot be imported when web is configured',
        );
      });
    }

    test('web requires a route', () {
      expectFailure(
        'app: quark\nweb: {}\n',
        'web.routes',
        problem: 'at least one route',
      );
    });

    for (final route in [
      'login',
      'https://example.com/login',
      '//example.com/login',
    ]) {
      test('web rejects application route $route', () {
        expectFailure(
          'app: quark\nweb:\n  routes: ["$route"]\n',
          'web.routes[0]',
          problem: 'absolute application path',
        );
      });
    }

    test('web rejects duplicate routes', () {
      expectFailure(
        'app: quark\nweb:\n  routes: [/files, /files]\n',
        'web.routes[1]',
        problem: 'duplicate route',
      );
    });

    test('web rejects an empty command', () {
      expectFailure(
        'app: quark\nweb:\n  routes: [/login]\n  build:\n    command: []\n',
        'web.build.command',
        problem: 'nonempty command',
      );
    });

    test('web rejects a port outside its range', () {
      expectFailure(
        'app: quark\nweb:\n  routes: [/login]\n  serve: {port: 65536}\n',
        'web.serve.port',
        problem: '0 to 65535',
      );
    });

    test('web rejects a non-positive timeout', () {
      expectFailure(
        'app: quark\nweb:\n  routes: [/login]\n  readiness: {timeoutSeconds: 0}\n',
        'web.readiness.timeoutSeconds',
        problem: 'greater than 0',
      );
    });

    test('web rejects a non-integer viewport width', () {
      expectFailure(
        'app: quark\nweb:\n  routes: [/login]\n  viewport: {width: 12.5}\n',
        'web.viewport.width',
        problem: 'positive integer',
      );
    });

    test('web rejects a non-positive viewport scale', () {
      expectFailure(
        'app: quark\nweb:\n  routes: [/login]\n  viewport: {deviceScaleFactor: -1}\n',
        'web.viewport.deviceScaleFactor',
        problem: 'greater than 0',
      );
    });

    test('web auth rejects fields from another step kind', () {
      expectFailure(
        'app: quark\nweb:\n  routes: [/files]\n  auth:\n    url: /login\n    steps:\n      - type: click\n        selector: button\n        valueFromEnv: SECRET\n',
        'web.auth.steps[0].valueFromEnv',
        problem: 'unknown key',
      );
    });

    test('web type auth requires an environment name', () {
      expectFailure(
        'app: quark\nweb:\n  routes: [/files]\n  auth:\n    url: /login\n    steps:\n      - type: type\n        selector: input\n',
        'web.auth.steps[0].valueFromEnv',
        problem: 'is required',
      );
    });

    test('web auth requires at least one step', () {
      expectFailure(
        'app: quark\nweb:\n  routes: [/files]\n  auth:\n    url: /login\n    steps: []\n',
        'web.auth.steps',
        problem: 'at least one step',
      );
    });

    test('a source without a directory', () {
      expectFailure(
        'app: quark\nsources:\n  attest: {}\n',
        'sources.attest.dir',
        problem: 'is required',
      );
    });

    test('a route pattern without a leading slash', () {
      expectFailure(
        'app: quark\nroutes:\n  patterns:\n    - /ok\n    - files\n',
        'routes.patterns[1]',
        line: 5,
        problem: 'must start with "/"',
      );
    });

    test('a route pattern with a bad regular expression', () {
      expectFailure(
        'app: quark\nroutes:\n  patterns: ["/x/:id([a-)"]\n',
        'routes.patterns[0]',
        line: 3,
        problem: 'invalid regular expression',
      );
    });

    test('weights that do not sum to 1', () {
      expectFailure(
        'app: quark\nscoring:\n  weights: {a11y: 0.5, perf: 0.4}\n',
        'scoring.weights',
        line: 3,
        problem: 'must sum to 1',
      );
    });

    test('a weight above 1', () {
      expectFailure(
        'app: quark\nscoring:\n  weights: {a11y: 1.5}\n',
        'scoring.weights.a11y',
      );
    });

    test('control points with p10 not below the median', () {
      expectFailure(
        'app: quark\nscoring:\n  metrics:\n    frame: {p10: 16, median: 16}\n',
        'scoring.metrics.frame',
        line: 4,
        problem: 'must be less than median',
      );
    });

    test('a non-positive control point', () {
      expectFailure(
        'app: quark\nscoring:\n  metrics:\n    frame: {p10: 0, median: 16}\n',
        'scoring.metrics.frame.p10',
      );
    });

    test('a missing control point', () {
      expectFailure(
        'app: quark\nscoring:\n  metrics:\n    frame: {p10: 8}\n',
        'scoring.metrics.frame.median',
        problem: 'is required',
      );
    });

    test('an unknown severity lists the choices', () {
      expectFailure(
        'app: quark\ngate:\n  minSeverity: high\n',
        'gate.minSeverity',
        problem: 'expected one of critical, serious, moderate, minor, info',
      );
    });

    test('a negative score drop', () {
      expectFailure(
        'app: quark\ngate:\n  maxScoreDrop: {perf: -1}\n',
        'gate.maxScoreDrop.perf',
      );
    });

    test('a YAML syntax error', () {
      expectFailure('app: quark\ngate: [\n', '(root)', problem: 'invalid YAML');
    });

    test('a duplicate key', () {
      expectFailure('app: a\napp: b\n', '(root)', line: 2);
    });

    test('describe renders the location', () {
      expect(
        describe(failed('app: quark\napps: x\n')),
        startsWith('config: apps (line 2, column 1): unknown key'),
      );
    });
  });
}
