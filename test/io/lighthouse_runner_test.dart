import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flighthouse/src/config/config.dart';
import 'package:flighthouse/src/io/browser.dart';
import 'package:flighthouse/src/io/lighthouse_runner.dart';
import 'package:flighthouse/src/io/web_build.dart';
import 'package:flighthouse/src/result/failure.dart';
import 'package:flighthouse/src/result/result.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _routes = ['/files', '/photos?album=a/../../b#top'];
const _crashFixtures = 'test/fixtures/lighthouse/13.5.0/target-crashed';
const _viewport = WebViewportConfig(
  width: 1440,
  height: 900,
  deviceScaleFactor: 2.5,
);
final _origin = Uri.parse('http://127.0.0.1:4321/');
final _browser = BrowserSession(
  BrowserBindings(
    info: _info,
    navigate: (_, _) async => fail('lighthouse runner drove the browser'),
    waitForFirstFrame: (_) async => fail('lighthouse runner drove the browser'),
    currentUrl: () => fail('lighthouse runner drove the browser'),
    waitForSelector: (_, _) async =>
        fail('lighthouse runner drove the browser'),
    click: (_) async => fail('lighthouse runner drove the browser'),
    focus: (_) async => fail('lighthouse runner drove the browser'),
    waitForFocus: (_, _) async => fail('lighthouse runner drove the browser'),
    settleInput: () async => fail('lighthouse runner drove the browser'),
    replaceInput: (_, _) async => fail('lighthouse runner drove the browser'),
    readInput: (_) async => fail('lighthouse runner drove the browser'),
    evaluate: (_, _) async => fail('lighthouse runner drove the browser'),
    close: () async => fail('lighthouse runner drove the browser'),
  ),
);
const _info = BrowserInfo(
  installation: BrowserInstallation(
    cachePath: '/cache/chrome',
    executablePath: '/cache/chrome/chrome',
    version: '152.0.0',
  ),
  browserVersion: 'Chrome/152.0.0',
  debuggingPort: 40123,
);

void main() {
  late Directory output;

  setUp(() async {
    output = await Directory.systemTemp.createTemp('flighthouse-lighthouse');
  });

  tearDown(() => output.delete(recursive: true));

  test('runs one argv command per route and writes a hashed result', () async {
    final recorder = Recorder((arguments) async {
      final url = arguments.firstWhere(
        (argument) => argument.startsWith('http://'),
      );
      return ProcessResult(1, 0, lighthouseReport(url), '');
    });
    File(p.join(output.path, 'stale.json')).writeAsStringSync('{}');

    final result = await _run(output.path, recorder.call);

    expect(result, isA<Ok<List<String>, Failure>>());
    expect(recorder.calls, hasLength(2));
    expect(recorder.calls.map((call) => call.executable), ['npx', 'npx']);
    expect(recorder.calls.map((call) => call.workingDirectory), [null, null]);
    expect(recorder.calls[0].arguments, _expectedArguments(_routes[0]));
    expect(recorder.calls[1].arguments, _expectedArguments(_routes[1]));
    for (final route in _routes) {
      final name = _artifactName(route);
      final file = File(p.join(output.path, name));
      final url = _origin.resolve(route).toString();
      expect(name, matches(RegExp(r'^[0-9a-f]{64}\.json$')));
      expect(file.readAsStringSync(), lighthouseReport(url));
      final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      final audits = json['audits'] as Map<String, Object?>;
      final scored = audits['accessibility-audit'] as Map<String, Object?>;
      final manual = audits['manual-audit'] as Map<String, Object?>;
      expect(scored['score'], 0);
      expect(manual['score'], isNull);
      expect(json['fetchTime'], '2026-10-08T00:00:00.000Z');
    }
    expect(File(p.join(output.path, 'stale.json')).existsSync(), isFalse);
    expect(Directory(p.join(output.path, 'photos')).existsSync(), isFalse);
    expect(Directory(output.path).listSync().whereType<File>(), hasLength(2));
  });

  test('passes the configured throttling to Lighthouse', () async {
    final recorder = Recorder((arguments) async {
      final url = arguments.firstWhere(
        (argument) => argument.startsWith('http://'),
      );
      return ProcessResult(1, 0, lighthouseReport(url), '');
    });

    final result = await _run(
      output.path,
      recorder.call,
      routes: [_routes.first],
      throttling: (
        rttMs: 150,
        throughputKbps: 1638.4,
        cpuSlowdownMultiplier: 4,
      ),
    );

    expect(result, isA<Ok<List<String>, Failure>>());
    expect(
      recorder.calls.single.arguments,
      _expectedArguments(
        _routes.first,
        rttMs: '150',
        throughputKbps: '1638.4',
        cpuSlowdownMultiplier: '4',
      ),
    );
  });

  test('rejects a runtime error without writing a file', () async {
    final recorder = Recorder((arguments) async {
      final url = arguments.firstWhere(
        (argument) => argument.startsWith('http://'),
      );
      return ProcessResult(
        1,
        0,
        lighthouseReport(
          url,
          runtimeError: const {
            'code': 'NO_FCP',
            'message': 'No first contentful paint',
          },
        ),
        '',
      );
    });

    final result = await _run(
      output.path,
      recorder.call,
      routes: const ['/files'],
    );

    final failure = (result as Err<List<String>, Failure>).error;
    expect(failure, isA<AdapterFailure>());
    expect(describe(failure), contains('/files'));
    expect(describe(failure), contains('NO_FCP'));
    expect(describe(failure), contains('No first contentful paint'));
    expect(_jsonFiles(output), isEmpty);
  });

  test(
    'rejects a redirected final URL and keeps the requested route',
    () async {
      const route = '/files';
      final displayed = _origin.resolve('/login').toString();
      final recorder = Recorder(
        (_) async => ProcessResult(1, 0, lighthouseReport(displayed), ''),
      );

      final result = await _run(
        output.path,
        recorder.call,
        routes: const [route],
      );

      final failure = (result as Err<List<String>, Failure>).error;
      expect(failure, isA<AdapterFailure>());
      expect(describe(failure), contains(route));
      expect(describe(failure), contains(displayed));
      expect(describe(failure), isNot(contains('s3cret-value')));
      expect(_jsonFiles(output), isEmpty);
    },
  );

  test('rejects unusable JSON when the process exits 0', () async {
    final recorder = Recorder((_) async => ProcessResult(1, 0, '{nope', ''));

    final result = await _run(
      output.path,
      recorder.call,
      routes: const ['/files'],
    );

    final failure = (result as Err<List<String>, Failure>).error;
    expect(failure, isA<AdapterFailure>());
    expect(describe(failure), contains('/files'));
    expect(describe(failure), contains('not valid JSON'));
    expect(_jsonFiles(output), isEmpty);
  });

  test('rejects a report missing required audit structure', () async {
    final recorder = Recorder((arguments) async {
      final url = arguments.firstWhere(
        (argument) => argument.startsWith('http://'),
      );
      return ProcessResult(
        1,
        0,
        lighthouseReport(url, accessibility: false),
        '',
      );
    });

    final result = await _run(
      output.path,
      recorder.call,
      routes: const ['/files'],
    );

    final failure = (result as Err<List<String>, Failure>).error;
    expect(failure, isA<AdapterFailure>());
    expect(describe(failure), contains('accessibility'));
    expect(_jsonFiles(output), isEmpty);
  });

  test('reports a nonzero exit without accepting its output', () async {
    final recorder = Recorder(
      (_) async => ProcessResult(
        1,
        1,
        lighthouseReport('http://127.0.0.1/files'),
        'audit failed\nmore',
      ),
    );
    File(p.join(output.path, 'stale.json'))
      ..parent.createSync()
      ..writeAsStringSync('keep');

    final result = await _run(
      output.path,
      recorder.call,
      routes: const ['/files'],
    );

    final failure = (result as Err<List<String>, Failure>).error;
    expect(failure, isA<ProcessFailure>());
    expect(describe(failure), contains('exited with code 1'));
    expect(describe(failure), contains('audit failed'));
    expect(describe(failure), contains('--disable-storage-reset'));
    expect(describe(failure), isNot(contains('more')));
    expect(File(p.join(output.path, 'stale.json')).readAsStringSync(), 'keep');
    expect(Directory(output.path).listSync().whereType<File>(), hasLength(1));
  });

  test('names a renderer crash recorded from a real Lighthouse run', () async {
    final recorder = Recorder(
      (_) async => ProcessResult(
        1,
        1,
        File(p.join(_crashFixtures, 'stdout.json')).readAsStringSync(),
        File(p.join(_crashFixtures, 'stderr.txt')).readAsStringSync(),
      ),
    );

    final result = await _run(
      output.path,
      recorder.call,
      routes: const ['/files'],
    );

    final failure = (result as Err<List<String>, Failure>).error;
    final message = describe(failure);
    expect(failure, isA<AdapterFailure>());
    expect(message, startsWith('lighthouse: /files: '));
    expect(message, contains('renderer crashed'));
    expect(message, contains('TARGET_CRASHED'));
    expect(message, contains('memory'));
    expect(message, contains('load'));
    expect(message, contains('sandbox'));
    expect(message, isNot(contains('Found existing Chrome')));
    expect(_jsonFiles(output), isEmpty);
  });

  test('reports the runtime error of a nonzero exit', () async {
    final recorder = Recorder(
      (arguments) async => ProcessResult(
        1,
        1,
        lighthouseReport(
          arguments.firstWhere((argument) => argument.startsWith('http://')),
          runtimeError: const {
            'code': 'NO_FCP',
            'message': 'No first contentful paint',
          },
        ),
        'LH:status Connecting to browser\nRuntime error encountered',
      ),
    );

    final result = await _run(
      output.path,
      recorder.call,
      routes: const ['/files'],
    );

    final failure = (result as Err<List<String>, Failure>).error;
    expect(failure, isA<AdapterFailure>());
    expect(
      describe(failure),
      'lighthouse: /files: Lighthouse reported a runtime error: '
      'NO_FCP: No first contentful paint',
    );
    expect(_jsonFiles(output), isEmpty);
  });

  test('a missing executable is a missing Lighthouse tool', () async {
    final recorder = Recorder(
      (_) async => throw const ProcessException('lighthouse', [
        'http://127.0.0.1/files',
      ], 'No such file or directory: s3cret-value'),
    );

    final result = await _run(
      output.path,
      recorder.call,
      routes: const ['/files'],
    );

    final failure = (result as Err<List<String>, Failure>).error;
    expect(failure, isA<MissingToolFailure>());
    expect(
      describe(failure),
      'Lighthouse not found. Install it with: npm install -g lighthouse',
    );
    expect(describe(failure), isNot(contains('s3cret-value')));
    expect(recorder.calls.single.workingDirectory, isNull);
    expect(_jsonFiles(output), isEmpty);
  });

  test('a failed later route publishes nothing', () async {
    var calls = 0;
    final recorder = Recorder((arguments) async {
      calls++;
      final url = arguments.firstWhere(
        (argument) => argument.startsWith('http://'),
      );
      if (calls == 1) return ProcessResult(1, 0, lighthouseReport(url), '');
      return ProcessResult(
        1,
        0,
        lighthouseReport(
          url,
          runtimeError: const {
            'code': 'CHROME_INTERSTITIAL_ERROR',
            'message': 'redirected',
          },
        ),
        '',
      );
    });
    File(p.join(output.path, 'stale.json')).writeAsStringSync('keep');

    final result = await _run(output.path, recorder.call);

    expect(result, isA<Err<List<String>, Failure>>());
    expect(calls, 2);
    expect(File(p.join(output.path, 'stale.json')).readAsStringSync(), 'keep');
    expect(
      File(p.join(output.path, _artifactName(_routes.first))).existsSync(),
      isFalse,
    );
  });
}

Future<Result<List<String>, Failure>> _run(
  String outputDir,
  ProcessRun run, {
  List<String> routes = _routes,
  LighthouseThrottling throttling = defaultLighthouseThrottling,
}) => runLighthouseRoutes(
  lighthouse: WebLighthouseConfig(
    command: const ['npx', 'lighthouse'],
    throttling: throttling,
  ),
  viewport: _viewport,
  browser: _browser,
  origin: _origin,
  routes: routes,
  outputDir: outputDir,
  run: run,
);

List<String> _expectedArguments(
  String route, {
  String rttMs = '40',
  String throughputKbps = '10240',
  String cpuSlowdownMultiplier = '1',
}) => [
  'lighthouse',
  _origin.resolve(route).toString(),
  '--hostname=127.0.0.1',
  '--port=40123',
  '--output=json',
  '--disable-storage-reset',
  '--form-factor=desktop',
  '--screenEmulation.mobile=false',
  '--screenEmulation.width=1440',
  '--screenEmulation.height=900',
  '--screenEmulation.deviceScaleFactor=2.5',
  '--throttling.rttMs=$rttMs',
  '--throttling.throughputKbps=$throughputKbps',
  '--throttling.cpuSlowdownMultiplier=$cpuSlowdownMultiplier',
  '--throttling.requestLatencyMs=0',
  '--throttling.downloadThroughputKbps=0',
  '--throttling.uploadThroughputKbps=0',
];

String _artifactName(String route) =>
    '${sha256.convert(utf8.encode(route))}.json';

Iterable<File> _jsonFiles(Directory directory) => directory
    .listSync()
    .whereType<File>()
    .where((file) => p.extension(file.path) == '.json');

String lighthouseReport(
  String finalUrl, {
  Object? runtimeError,
  bool accessibility = true,
}) => jsonEncode({
  'lighthouseVersion': '13.5.0',
  'requestedUrl': finalUrl,
  'finalDisplayedUrl': finalUrl,
  'categories': {
    'performance': _category(['performance-audit']),
    if (accessibility)
      'accessibility': _category(['accessibility-audit', 'manual-audit']),
    'best-practices': _category(['best-practices-audit']),
  },
  'audits': {
    'performance-audit': _audit('performance-audit', 0.5, 'numeric'),
    'accessibility-audit': _audit('accessibility-audit', 0, 'binary'),
    'manual-audit': _audit('manual-audit', null, 'manual'),
    'best-practices-audit': _audit('best-practices-audit', 1, 'binary'),
  },
  'fetchTime': '2026-10-08T00:00:00.000Z',
  'runtimeError': ?runtimeError,
});

Map<String, Object?> _category(List<String> ids) => {
  'auditRefs': [
    for (final id in ids) {'id': id, 'weight': id == 'manual-audit' ? 0 : 1},
  ],
};

Map<String, Object?> _audit(String id, Object? score, String mode) => {
  'id': id,
  'title': id,
  'score': score,
  'scoreDisplayMode': mode,
};

final class Recorder {
  Recorder(this._respond);

  final Future<ProcessResult> Function(List<String> arguments) _respond;
  final List<
    ({String executable, List<String> arguments, String? workingDirectory})
  >
  calls = [];

  Future<ProcessResult> call(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) {
    calls.add((
      executable: executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
    ));
    return _respond(arguments);
  }
}
