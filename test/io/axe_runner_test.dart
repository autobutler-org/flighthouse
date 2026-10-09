import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flighthouse/src/config/config.dart';
import 'package:flighthouse/src/io/axe_runner.dart';
import 'package:flighthouse/src/io/axe_script.dart';
import 'package:flighthouse/src/io/browser.dart';
import 'package:flighthouse/src/result/failure.dart';
import 'package:flighthouse/src/result/result.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _routes = ['/files', '/photos?album=a/../../b#top'];
final _origin = Uri.parse('http://127.0.0.1:4321/');
const _readiness = WebReadinessConfig(
  timeout: Duration(seconds: 5),
  selector: null,
);
const _localScript = 'window.__flighthouseAxe = "local-script";';
const _pinnedScript = '/* axe-core 4.11.1 */';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('flighthouse-axe');
  });

  tearDown(() => root.delete(recursive: true));

  test('injects a local script and passes ancestry', () async {
    File(p.join(root.path, 'tools', 'axe.min.js'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(_localScript);
    final browser = _Browser();

    final result = await _run(
      root,
      browser,
      axe: const WebAxeConfig(version: '9.9.9', scriptPath: 'tools/axe.min.js'),
    );

    expect(result, isA<Ok<List<String>, Failure>>());
    final runner = browser.scripts.where(
      (script) => script.contains('axe.run'),
    );
    expect(runner, hasLength(_routes.length));
    expect(
      runner.every(
        (script) => script.contains('axe.run(document, { ancestry: true })'),
      ),
      isTrue,
    );
    expect(
      browser.arguments.where((args) => args.isNotEmpty),
      everyElement([_localScript]),
    );
    expect(browser.closes, 0);
  });

  test('writes a large result unchanged under a safe name', () async {
    final browser = _Browser();
    final outputDir = p.join(root.path, 'raw', 'axe');
    Directory(p.join(outputDir, 'photos')).createSync(recursive: true);
    File(p.join(outputDir, 'stale.json')).writeAsStringSync('{}');

    final result = await _run(root, browser, outputDir: outputDir);

    expect(result, isA<Ok<List<String>, Failure>>());
    expect(browser.axeResults, hasLength(_routes.length));
    expect(Directory(p.join(outputDir, 'photos')).existsSync(), isFalse);
    expect(File(p.join(outputDir, 'stale.json')).existsSync(), isFalse);
    for (var index = 0; index < _routes.length; index++) {
      final route = _routes[index];
      final name = _artifactName(route);
      final file = File(p.join(outputDir, name));
      expect(name, matches(RegExp(r'^[0-9a-f]{64}\.json$')));
      expect(name, isNot(contains('photos')));
      expect(file.readAsStringSync(), browser.axeResults[index]);
      expect(file.readAsStringSync(), contains('"#action-499"'));
      expect(file.readAsStringSync(), contains('["iframe","#shadow"]'));
      expect(file.readAsStringSync(), endsWith('\n'));
    }
    expect(
      Directory(outputDir).listSync().whereType<File>(),
      hasLength(_routes.length),
    );
  });

  test('downloads a pinned axe-core once and reuses the cache', () async {
    final downloads = <Uri>[];
    final browser = _Browser();
    final cacheDir = p.join(root.path, 'cache');

    final first = await _run(
      root,
      browser,
      axe: const WebAxeConfig(version: '4.11.1', scriptPath: null),
      cacheDir: cacheDir,
      download: (url) async {
        downloads.add(url);
        return _pinnedScript;
      },
    );
    final second = await _run(
      root,
      _Browser(),
      axe: const WebAxeConfig(version: '4.11.1', scriptPath: null),
      cacheDir: cacheDir,
      download: (url) async {
        downloads.add(url);
        return 'should not download again';
      },
    );

    expect(first, isA<Ok<List<String>, Failure>>());
    expect(second, isA<Ok<List<String>, Failure>>());
    expect(downloads, [
      Uri.parse(
        'https://cdnjs.cloudflare.com/ajax/libs/axe-core/4.11.1/axe.min.js',
      ),
    ]);
    expect(
      File(p.join(cacheDir, '4.11.1', 'axe.min.js')).readAsStringSync(),
      _pinnedScript,
    );
    expect(
      browser.arguments.where((args) => args.isNotEmpty),
      everyElement([_pinnedScript]),
    );
  });

  test('a failed download does not write an axe audit', () async {
    final browser = _Browser();
    final outputDir = p.join(root.path, 'raw', 'axe');

    final result = await _run(
      root,
      browser,
      axe: const WebAxeConfig(version: '4.11.1', scriptPath: null),
      outputDir: outputDir,
      download: (_) async => throw const SocketException('Connection refused'),
    );

    final failure = (result as Err<List<String>, Failure>).error;
    expect(failure, isA<IoFailure>());
    expect(describe(failure), contains('could not download axe-core'));
    expect(describe(failure), contains('4.11.1/axe.min.js'));
    expect(describe(failure), contains('Connection refused'));
    expect(Directory(outputDir).existsSync(), isFalse);
    expect(
      browser.scripts.where((script) => script.contains('axe.run')),
      isEmpty,
    );
    expect(browser.closes, 0);
  });

  test('a missing pinned release is a missing-tool failure', () async {
    final result = await _run(
      root,
      _Browser(),
      axe: const WebAxeConfig(version: '4.11.1', scriptPath: null),
      download: (url) async => throw HttpException('HTTP 404', uri: url),
    );

    final failure = (result as Err<List<String>, Failure>).error;
    expect(failure, isA<MissingToolFailure>());
    expect(describe(failure), contains('axe-core 4.11.1 not found'));
    expect(describe(failure), contains('web.axe.scriptPath'));
  });

  test('an unsafe version is not used as a cache path', () async {
    var downloaded = false;
    final cacheDir = p.join(root.path, 'cache');
    final escaped = File(p.join(root.path, 'outside', 'axe.min.js'));

    final result = await acquireAxeScript(
      config: const WebAxeConfig(version: '../outside', scriptPath: null),
      configBaseDir: root.path,
      cacheDir: cacheDir,
      download: (_) async {
        downloaded = true;
        return _pinnedScript;
      },
    );

    expect(result, isA<Err<String, Failure>>());
    expect(downloaded, isFalse);
    expect(escaped.existsSync(), isFalse);
  });

  test('a different displayed route fails with both paths', () async {
    _writeLocalScript(root);
    final browser = _Browser(
      relocate: (target) => target.replace(path: '/login'),
    );
    final outputDir = p.join(root.path, 'raw', 'axe');

    final result = await _run(
      root,
      browser,
      routes: const ['/files'],
      outputDir: outputDir,
    );

    final failure = (result as Err<List<String>, Failure>).error;
    expect(describe(failure), contains('/files'));
    expect(describe(failure), contains('/login'));
    expect(Directory(outputDir).existsSync(), isFalse);
    expect(_artifactFile(outputDir, '/files').existsSync(), isFalse);
    expect(_artifactFile(outputDir, '/login').existsSync(), isFalse);
  });

  test('an axe result for another URL is not relabeled', () async {
    _writeLocalScript(root);
    final browser = _Browser(
      onEvaluate: (script, _) async {
        if (!script.contains('axe.run')) return 2;
        return _axeDocument('http://127.0.0.1:4321/login');
      },
    );
    final outputDir = p.join(root.path, 'raw', 'axe');

    final result = await _run(
      root,
      browser,
      routes: const ['/files'],
      outputDir: outputDir,
    );

    final failure = (result as Err<List<String>, Failure>).error;
    expect(
      describe(failure),
      contains(
        'displayed URL was http://127.0.0.1:4321/login; requested /files',
      ),
    );
    expect(Directory(outputDir).existsSync(), isFalse);
  });

  test('invalid axe JSON is not stored', () async {
    _writeLocalScript(root);
    final browser = _Browser(
      onEvaluate: (script, _) async => script.contains('axe.run') ? '{nope' : 2,
    );
    final outputDir = p.join(root.path, 'raw', 'axe');

    final result = await _run(root, browser, outputDir: outputDir);

    final failure = (result as Err<List<String>, Failure>).error;
    expect(failure, isA<AdapterFailure>());
    expect(describe(failure), contains('not valid JSON'));
    expect(Directory(outputDir).existsSync(), isFalse);
  });

  test('a result missing an engine or result field is not stored', () async {
    _writeLocalScript(root);
    final browser = _Browser(
      onEvaluate: (script, _) async {
        if (!script.contains('axe.run')) return 2;
        return jsonEncode({
          'testEngine': {'name': 'axe-core', 'version': '4.11.1'},
          'url': _origin.resolve('/files').toString(),
          'violations': <Object?>[],
          'incomplete': <Object?>[],
          'inapplicable': <Object?>[],
        });
      },
    );
    final outputDir = p.join(root.path, 'raw', 'axe');

    final result = await _run(
      root,
      browser,
      routes: const ['/files'],
      outputDir: outputDir,
    );

    final failure = (result as Err<List<String>, Failure>).error;
    expect(describe(failure), contains(r'$.passes'));
    expect(Directory(outputDir).existsSync(), isFalse);
  });

  test('a failed injection does not write an audit', () async {
    _writeLocalScript(root);
    final browser = _Browser(
      onEvaluate: (script, _) async {
        if (script.contains('axe.run')) {
          throw Exception('axe-core did not load');
        }
        return 2;
      },
    );

    final result = await _run(root, browser, routes: const ['/files']);

    final failure = (result as Err<List<String>, Failure>).error;
    expect(describe(failure), contains('axe-core did not load'));
    expect(browser.closes, 0);
  });

  test('a renderer crash during axe names the route and the crash', () async {
    _writeLocalScript(root);
    final crash = Completer<void>();
    final browser = _Browser(
      crash: crash.future,
      onEvaluate: (script, _) {
        if (!script.contains('axe.run')) return Future.value(2);
        crash.complete();
        return Completer<Object?>().future;
      },
    );

    final result = await _run(
      root,
      browser,
      routes: const ['/files'],
    ).timeout(const Duration(seconds: 1));

    final failure = (result as Err<List<String>, Failure>).error;
    expect(
      describe(failure),
      'could not run axe-core /files: $chromeRendererCrashedReason',
    );
  });

  test('axe waits for semantics and the readiness selector', () async {
    _writeLocalScript(root);
    final skipped = _Browser(
      onEvaluate: (script, _) async => script.contains('axe.run') ? '{}' : 0,
    );

    final noSemantics = await _run(root, skipped, routes: const ['/files']);

    expect(
      describe((noSemantics as Err<List<String>, Failure>).error),
      contains('no Flutter semantics'),
    );
    expect(skipped.axeResults, isEmpty);

    final waiting = _Browser(selectorError: 'not ready');
    final notReady = await _run(
      root,
      waiting,
      routes: const ['/files'],
      readiness: const WebReadinessConfig(
        timeout: Duration(seconds: 5),
        selector: '[role="main"]',
      ),
    );

    expect(
      describe((notReady as Err<List<String>, Failure>).error),
      contains('[role="main"]'),
    );
    expect(waiting.axeResults, isEmpty);
  });

  test('an absolute script path is injected as stored', () async {
    final script = File(p.join(root.path, 'absolute.min.js'))
      ..writeAsStringSync(_localScript);
    final browser = _Browser();

    final result = await _run(
      root,
      browser,
      axe: WebAxeConfig(version: '4.11.1', scriptPath: script.path),
      routes: const ['/files'],
    );

    expect(result, isA<Ok<List<String>, Failure>>());
    expect(browser.arguments.where((args) => args.isNotEmpty).single, [
      _localScript,
    ]);
  });

  test('a non-text axe result is not stored', () async {
    final browser = _Browser(
      onEvaluate: (script, _) async => script.contains('axe.run') ? 5 : 2,
    );

    final result = await _run(root, browser, routes: const ['/files']);

    expect(
      describe((result as Err<List<String>, Failure>).error),
      contains('instead of JSON text'),
    );
  });

  test('downloadAxeScript reads a loopback response and rejects 404', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.statusCode = request.uri.path == '/missing.js'
          ? HttpStatus.notFound
          : HttpStatus.ok;
      request.response.write(_pinnedScript);
      await request.response.close();
    });
    final base = Uri.parse('http://127.0.0.1:${server.port}');

    expect(await downloadAxeScript(base.resolve('/axe.min.js')), _pinnedScript);
    expect(
      downloadAxeScript(base.resolve('/missing.js')),
      throwsA(isA<HttpException>()),
    );
  });
}

Future<Result<List<String>, Failure>> _run(
  Directory root,
  _Browser browser, {
  WebAxeConfig? axe,
  List<String> routes = _routes,
  String? outputDir,
  String? cacheDir,
  WebReadinessConfig readiness = _readiness,
  AxeScriptDownload? download,
}) {
  final config =
      axe ?? const WebAxeConfig(version: '4.11.1', scriptPath: 'axe.min.js');
  if (config.scriptPath == 'axe.min.js') _writeLocalScript(root);
  return runAxeRoutes(
    axe: config,
    configBaseDir: root.path,
    readiness: readiness,
    browser: browser.session,
    origin: _origin,
    routes: routes,
    outputDir: outputDir ?? p.join(root.path, 'out'),
    cacheDir: cacheDir ?? p.join(root.path, 'cache'),
    download:
        download ??
        ((_) async => throw const SocketException('unexpected download')),
  );
}

void _writeLocalScript(Directory root) {
  final file = File(p.join(root.path, 'axe.min.js'));
  if (!file.existsSync()) file.writeAsStringSync(_localScript);
}

String _artifactName(String route) =>
    '${sha256.convert(utf8.encode(route))}.json';

File _artifactFile(String outputDir, String route) =>
    File(p.join(outputDir, _artifactName(route)));

String largeAxeResult(String pageUrl) {
  final nodes = <Object?>[
    for (var index = 0; index < 500; index++)
      {
        'html': '<button id="action-$index">',
        'impact': 'critical',
        'target': [
          ['iframe', '#shadow'],
          '#action-$index',
        ],
        'ancestry': [
          ['iframe', '#shadow'],
          'flutter-view > flt-semantics:nth-child(${index + 1})',
        ],
      },
  ];
  return '${jsonEncode({
    'inapplicable': [
      {'id': 'accesskeys'},
    ],
    'incomplete': [
      {
        'id': 'color-contrast',
        'nodes': [nodes.first],
      },
    ],
    'passes': [
      {'id': 'document-title', 'nodes': <Object?>[]},
    ],
    'testEngine': {'name': 'axe-core', 'version': '4.11.1'},
    'url': pageUrl,
    'violations': [
      {'id': 'button-name', 'impact': 'critical', 'nodes': nodes},
    ],
  })}\n';
}

String _axeDocument(String pageUrl) => jsonEncode({
  'testEngine': {'name': 'axe-core', 'version': '4.11.1'},
  'url': pageUrl,
  'violations': <Object?>[],
  'passes': <Object?>[],
  'incomplete': <Object?>[],
  'inapplicable': <Object?>[],
});

final class _Browser {
  _Browser({this.relocate, this.onEvaluate, this.selectorError, this.crash});

  final Uri Function(Uri target)? relocate;
  final Future<Object?> Function(String script, List<Object?> arguments)?
  onEvaluate;
  final String? selectorError;
  final Future<void>? crash;
  final List<String> scripts = [];
  final List<List<Object?>> arguments = [];
  final List<String> axeResults = [];
  int closes = 0;
  Uri url = _origin;

  late final BrowserSession session = BrowserSession(
    BrowserBindings(
      info: const BrowserInfo(
        installation: BrowserInstallation(
          cachePath: '/cache/chrome',
          executablePath: '/cache/chrome/chrome',
          version: '152.0.0',
        ),
        browserVersion: 'Chrome/152.0.0',
        debuggingPort: 40123,
      ),
      navigate: (target, _) async {
        url = relocate?.call(target) ?? target;
      },
      waitForFirstFrame: (_) async {},
      currentUrl: () => url.toString(),
      waitForSelector: (selector, _) async {
        if (selectorError != null) {
          throw Exception('$selectorError: $selector');
        }
      },
      click: (_) async {},
      focus: (_) async {},
      waitForFocus: (_, _) async {},
      settleInput: () async {},
      replaceInput: (_, _) async {},
      readInput: (_) async => '',
      evaluate: (script, args) async {
        scripts.add(script);
        arguments.add(args);
        if (onEvaluate != null) {
          final value = await onEvaluate!(script, args);
          if (value is String && script.contains('axe.run')) {
            axeResults.add(value);
          }
          return value;
        }
        if (!script.contains('axe.run')) return 3;
        final raw = largeAxeResult(url.toString());
        axeResults.add(raw);
        return raw;
      },
      close: () async {
        closes++;
      },
      rendererCrashed: () => crash ?? Completer<void>().future,
    ),
  );
}
