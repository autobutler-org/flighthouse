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
    });

    test('treats empty sections as absent', () {
      final empty = parsed('app: quark\nsources:\nroutes:\nscoring:\ngate:\n');
      expect(empty.sources, isEmpty);
      expect(empty.scoring.weights, defaultCategoryWeights);
      expect(empty.gate.minSeverity, Severity.minor);
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
