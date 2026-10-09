import 'dart:io';

import 'package:flighthouse/src/config/config.dart';
import 'package:flighthouse/src/io/browser.dart';
import 'package:flighthouse/src/io/web_collection.dart';
import 'package:flighthouse/src/result/failure.dart';
import 'package:flighthouse/src/result/result.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _timeout = Duration(seconds: 1);

void main() {
  late Directory baseDir;

  setUp(() async {
    baseDir = await Directory.systemTemp.createTemp('flighthouse-collection');
    Directory(p.join(baseDir.path, 'app')).createSync();
  });

  tearDown(() => baseDir.delete(recursive: true));

  test('authenticates before collection in the same browser session', () async {
    final fake = CollectionBrowser();
    late BrowserViewport launchedViewport;
    late Uri origin;
    final result = await runWebCollection<String>(
      configBaseDir: baseDir.path,
      config: _config,
      environment: const {'USERNAME': 'owner', 'PASSWORD': 'password'},
      runProcess: _successfulBuild,
      launch: (viewport) async {
        launchedViewport = viewport;
        return Ok(fake.session);
      },
      collect: (browser, serverOrigin, routes) async {
        origin = serverOrigin;
        expect(browser, same(fake.session));
        expect(fake.authenticated, isTrue);
        expect(fake.url.path, '/files');
        expect(routes, ['/files', '/photos']);
        expect((await _request(serverOrigin)).statusCode, HttpStatus.ok);
        return const Ok('captured');
      },
      closeTimeout: _timeout,
    );

    expect(result, const Ok<String, Failure>('captured'));
    expect(launchedViewport.width, 1280);
    expect(launchedViewport.height, 800);
    expect(launchedViewport.deviceScaleFactor, 1);
    expect(
      fake.events.indexOf('click #submit'),
      lessThan(fake.events.indexOf('navigate /files')),
    );
    expect(fake.closes, 1);
    await expectLater(
      Socket.connect(origin.host, origin.port),
      throwsA(isA<SocketException>()),
    );
  });

  test('closes the browser and server after a collector failure', () async {
    final fake = CollectionBrowser();
    late Uri origin;
    final result = await runWebCollection<void>(
      configBaseDir: baseDir.path,
      config: _config,
      environment: const {'USERNAME': 'owner', 'PASSWORD': 'password'},
      runProcess: _successfulBuild,
      launch: (_) async => Ok(fake.session),
      collect: (_, serverOrigin, _) async {
        origin = serverOrigin;
        return const Err(
          ProcessFailure(
            command: 'lighthouse',
            exitCode: 1,
            stderr: 'audit failed',
          ),
        );
      },
      closeTimeout: _timeout,
    );

    expect(result, isA<Err<void, Failure>>());
    expect((result as Err<void, Failure>).error, isA<ProcessFailure>());
    expect(fake.closes, 1);
    await expectLater(
      Socket.connect(origin.host, origin.port),
      throwsA(isA<SocketException>()),
    );
  });

  test('does not launch a browser after a build failure', () async {
    var launches = 0;
    final result = await runWebCollection<void>(
      configBaseDir: baseDir.path,
      config: _config,
      environment: const {},
      runProcess: (_, _, {workingDirectory}) async =>
          ProcessResult(1, 1, '', 'build failed'),
      launch: (_) async {
        launches++;
        return Ok(CollectionBrowser().session);
      },
      collect: (_, _, _) async => const Ok(null),
      closeTimeout: _timeout,
    );
    expect(result, isA<Err<void, Failure>>());
    expect((result as Err<void, Failure>).error, isA<ProcessFailure>());
    expect(launches, 0);
  });
}

Future<ProcessResult> _successfulBuild(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async {
  File(p.join(workingDirectory!, 'build/web/index.html'))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('app');
  return ProcessResult(1, 0, '', '');
}

Future<HttpClientResponse> _request(Uri origin) async {
  final client = HttpClient();
  final response = await (await client.getUrl(origin)).close();
  await response.drain<void>();
  client.close(force: true);
  return response;
}

final _config = WebConfig(
  projectDir: 'app',
  build: WebBuildConfig(
    command: const ['flutter', 'build', 'web', '--release'],
    outputDir: 'build/web',
  ),
  serve: const WebServeConfig(port: 0),
  routes: const ['/files', '/photos'],
  readiness: const WebReadinessConfig(timeout: _timeout, selector: null),
  viewport: const WebViewportConfig(
    width: 1280,
    height: 800,
    deviceScaleFactor: 1,
  ),
  auth: WebAuthConfig(
    url: '/login',
    steps: const [
      WebTypeAuthStep(selector: '#username', valueFromEnv: 'USERNAME'),
      WebTypeAuthStep(selector: '#password', valueFromEnv: 'PASSWORD'),
      WebClickAuthStep(selector: '#submit'),
    ],
  ),
  lighthouse: WebLighthouseConfig(command: const ['lighthouse']),
  axe: const WebAxeConfig(version: '4.11.1', scriptPath: null),
);

final class CollectionBrowser {
  CollectionBrowser() {
    session = BrowserSession(
      BrowserBindings(
        info: _info,
        navigate: (target, _) async {
          events.add('navigate ${target.path}');
          url = target.path == '/files' && !authenticated
              ? target.resolve('/login')
              : target;
        },
        waitForFirstFrame: (_) async {},
        currentUrl: () => url.toString(),
        waitForSelector: (_, _) async {},
        click: (selector) async {
          events.add('click $selector');
          if (selector == '#submit') authenticated = true;
        },
        focus: (_) async {},
        waitForFocus: (_, _) async {},
        settleInput: () async {},
        replaceInput: (selector, value) async {
          values[selector] = value;
        },
        readInput: (selector) async => values[selector],
        evaluate: (_, _) async => 3,
        close: () async {
          closes++;
        },
      ),
    );
  }

  late final BrowserSession session;
  final List<String> events = [];
  final Map<String, String> values = {};
  Uri url = Uri.parse('http://127.0.0.1/');
  bool authenticated = false;
  int closes = 0;
}

const _installation = BrowserInstallation(
  cachePath: '/cache/chrome',
  executablePath: '/cache/chrome/152/chrome',
  version: '152.0.7977.42',
);
const _info = BrowserInfo(
  installation: _installation,
  browserVersion: 'Chrome/152.0.7977.42',
  debuggingPort: 40123,
);
