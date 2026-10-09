import 'dart:convert';
import 'dart:io';

import 'package:flighthouse/src/config/config.dart';
import 'package:flighthouse/src/io/axe_script.dart';
import 'package:flighthouse/src/io/browser.dart';
import 'package:flighthouse/src/io/puppeteer_browser.dart';
import 'package:flighthouse/src/result/result.dart';
import 'package:path/path.dart' as p;
import 'package:puppeteer/puppeteer.dart' as puppeteer;

const _axeRun = r'''
async (source) => {
  const parent = document.head || document.documentElement;
  const element = document.createElement('script');
  element.setAttribute('data-flighthouse-axe', 'true');
  element.textContent = source;
  parent.appendChild(element);
  if (typeof axe === 'undefined' || typeof axe.run !== 'function') {
    throw new Error('axe-core did not load');
  }
  const result = await axe.run(document, { ancestry: true });
  return JSON.stringify(result);
}
''';

const _page = '''
<!doctype html>
<html>
<head><title>chrome smoke</title></head>
<body>
<main>
<button id="unlabeled"></button>
<label>Name <input id="typed" type="text"></label>
</main>
<script>
  const typed = document.getElementById('typed');
  let attached = false;
  typed.addEventListener('pointerdown', () => {
    attached = true;
  });
  typed.addEventListener('input', () => {
    if (attached) return;
    attached = true;
    typed.value = '';
  });
  window.dispatchEvent(new Event('flutter-first-frame'));
</script>
</body>
</html>
''';

Future<void> main(List<String> args) async {
  final environment = Platform.environment;
  final cache = chromeCacheDirectory(
    home: environment['HOME'],
    userProfile: environment['USERPROFILE'],
    fallback: Directory.systemTemp.path,
  );
  final sandboxDisabled = chromeSandboxDisabled(environment);
  stdout.writeln(
    sandboxDisabled
        ? 'chrome sandbox disabled by $chromeNoSandboxSwitch'
        : 'chrome sandbox enabled',
  );
  if (args.contains('--acquire-only')) {
    final downloaded = await puppeteer.downloadChrome(cachePath: cache);
    stdout.writeln('chrome ${downloaded.version}');
    stdout.writeln('executable ${downloaded.executablePath}');
    return;
  }

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final subscription = server.listen((request) async {
    request.response.headers.contentType = ContentType.html;
    request.response.write(_page);
    await request.response.close();
  });
  final origin = Uri.parse('http://127.0.0.1:${server.port}/');
  try {
    final launched = await launchPuppeteerBrowser(
      cachePath: cache,
      viewport: const BrowserViewport(
        width: 1280,
        height: 800,
        deviceScaleFactor: 1,
      ),
      acquireTimeout: const Duration(minutes: 5),
      launchTimeout: const Duration(seconds: 60),
      environment: environment,
    );
    switch (launched) {
      case Err(:final error):
        stderr.writeln(error);
        exitCode = 1;
        return;
      case Ok(:final value):
        stdout.writeln('browser ${value.info.browserVersion}');
        stdout.writeln('chrome ${value.info.installation.version}');
        try {
          await _audit(value, origin);
        } finally {
          final closed = await value.close(
            timeout: const Duration(seconds: 30),
          );
          if (closed case Err(:final error)) {
            stderr.writeln(error);
            exitCode = 1;
          }
        }
    }
  } finally {
    await subscription.cancel();
    await server.close(force: true);
  }
}

Future<void> _audit(BrowserSession browser, Uri origin) async {
  final opened = await browser.open(
    origin,
    timeout: const Duration(seconds: 30),
  );
  if (opened case Err(:final error)) {
    stderr.writeln(error);
    exitCode = 1;
    return;
  }
  final typed = await browser.type(
    '#typed',
    'chrome smoke',
    timeout: const Duration(seconds: 30),
  );
  if (typed case Err(:final error)) {
    stderr.writeln(error);
    exitCode = 1;
    return;
  }
  stdout.writeln('typed into an input that attaches on tap');
  final acquired = await acquireAxeScript(
    config: const WebAxeConfig(version: '4.11.1', scriptPath: null),
    configBaseDir: Directory.current.path,
    cacheDir: defaultAxeCacheDir(),
  );
  switch (acquired) {
    case Err(:final error):
      stderr.writeln(error);
      exitCode = 1;
      return;
    case Ok(:final value):
      final evaluated = await browser.evaluateJson(
        _axeRun,
        arguments: [value],
        timeout: const Duration(seconds: 30),
      );
      switch (evaluated) {
        case Err(:final error):
          stderr.writeln(error);
          exitCode = 1;
        case Ok(:final value):
          await _writeResult(value);
      }
  }
}

Future<void> _writeResult(Object? value) async {
  if (value is! String) {
    stderr.writeln('axe returned ${value.runtimeType} instead of JSON text');
    exitCode = 1;
    return;
  }
  final Object? decoded = jsonDecode(value);
  if (decoded is! Map<String, dynamic>) {
    stderr.writeln('axe JSON was not an object');
    exitCode = 1;
    return;
  }
  final engine = decoded['testEngine'];
  final violations = decoded['violations'];
  final version = engine is Map<String, dynamic> ? engine['version'] : null;
  if (version is! String || version.isEmpty) {
    stderr.writeln('axe did not report a version');
    exitCode = 1;
    return;
  }
  if (violations is! List<dynamic> || violations.isEmpty) {
    stderr.writeln('axe returned no violations from the unlabeled button');
    exitCode = 1;
    return;
  }
  final output = File(p.join('build', 'chrome-smoke', 'axe.json'));
  await output.parent.create(recursive: true);
  await output.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(decoded)}\n',
  );
  stdout.writeln('axe $version');
  stdout.writeln('wrote ${output.path}');
}
