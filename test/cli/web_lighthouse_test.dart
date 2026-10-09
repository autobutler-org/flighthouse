import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flighthouse/src/cli/cli.dart';
import 'package:flighthouse/src/io/browser.dart';
import 'package:flighthouse/src/io/web_build.dart';
import 'package:flighthouse/src/io/web_collection.dart';
import 'package:flighthouse/src/result/result.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _secret = 's3cret-value';
const _routes = ['/files', '/photos?album=a/../../b#top'];

const _webConfig = '''
app: quark
sources:
  attest:
    dir: attest-out
web:
  projectDir: app
  build:
    command: [flutter, build, web, --release]
    outputDir: build/web
  routes:
    - /files
    - "/photos?album=a/../../b#top"
  viewport:
    width: 1280
    height: 800
    deviceScaleFactor: 1
  auth:
    url: /login
    steps:
      - type: type
        selector: "#password"
        valueFromEnv: FLIGHTHOUSE_PASSWORD
      - type: click
        selector: "#submit"
  lighthouse:
    command: [lighthouse]
''';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('flighthouse-web-lh');
  });

  tearDown(() => root.delete(recursive: true));

  test(
    'collect writes one lighthouse result per route and copies imports',
    () async {
      final workspace = Workspace(root);
      workspace.write('flighthouse.yaml', _webConfig);
      workspace.write('attest-out/sample.json', '{"tool":"attest"}\n');
      workspace.write('.flighthouse/raw/lighthouse/stale.json', '{}');
      final browser = RecordingBrowser();
      final script = Script((arguments) {
        final url = arguments.firstWhere(
          (argument) => argument.startsWith('http://'),
        );
        return lighthouseReport(url);
      });
      BrowserViewport? viewport;

      final run = await workspace.execute(
        ['collect'],
        runProcess: script.call,
        launchBrowser: (launched) async {
          viewport = launched;
          return Ok(browser.session);
        },
        platformEnvironment: const {'FLIGHTHOUSE_PASSWORD': _secret},
      );

      expect(run.code, exitPassed);
      expect(run.err, isEmpty);
      expect(run.out, contains('collected 1 attest file'));
      expect(run.out, contains('collected 2 lighthouse files'));
      expect(run.out, isNot(contains(_secret)));
      expect(
        workspace.read('.flighthouse/raw/attest/sample.json'),
        '{"tool":"attest"}\n',
      );
      expect(
        workspace.exists('.flighthouse/raw/lighthouse/stale.json'),
        isFalse,
      );
      expect(
        Directory(workspace.path('.flighthouse/raw/axe')).existsSync(),
        isFalse,
      );
      expect(browser.values['#password'], _secret);
      expect(browser.closes, 1);
      expect(viewport?.width, 1280);
      expect(viewport?.height, 800);
      expect(viewport?.deviceScaleFactor, 1);
      final lighthouse = script.calls.where(
        (call) => call.executable == 'lighthouse',
      );
      expect(lighthouse, hasLength(_routes.length));
      expect(
        script.calls.map((call) => call.executable),
        containsAll(['flutter', 'lighthouse']),
      );
      expect(script.calls.first.executable, 'flutter');
      expect(script.calls.first.arguments, ['build', 'web', '--release']);
      for (final call in script.calls) {
        expect(call.arguments.join('\n'), isNot(contains(_secret)));
      }
      final urls = [
        for (final call in lighthouse)
          call.arguments.singleWhere(
            (argument) => argument.startsWith('http://'),
          ),
      ];
      expect(Uri.parse(urls[0]).path, '/files');
      expect(Uri.parse(urls[1]).path, '/photos');
      expect(Uri.parse(urls[1]).query, 'album=a/../../b');
      expect(Uri.parse(urls[1]).fragment, 'top');
      expect(lighthouse.first.arguments, contains('--port=40123'));
      expect(lighthouse.first.arguments, contains('--disable-storage-reset'));
      expect(lighthouse.first.arguments, contains('--form-factor=desktop'));
      expect(
        lighthouse.first.arguments,
        contains('--screenEmulation.mobile=false'),
      );
      expect(
        lighthouse.first.arguments,
        contains('--screenEmulation.width=1280'),
      );
      expect(
        lighthouse.first.arguments,
        contains('--screenEmulation.height=800'),
      );
      expect(
        lighthouse.first.arguments,
        contains('--screenEmulation.deviceScaleFactor=1'),
      );
      expect(lighthouse.first.arguments, contains('--output=json'));
      expect(lighthouse.first.arguments, isNot(contains(_routes[1])));
      for (final route in _routes) {
        final name = '${sha256.convert(utf8.encode(route))}.json';
        final relative = '.flighthouse/raw/lighthouse/$name';
        expect(workspace.exists(relative), isTrue);
        final json =
            jsonDecode(workspace.read(relative)) as Map<String, Object?>;
        final audits = json['audits'] as Map<String, Object?>;
        final scored = audits['accessibility-audit'] as Map<String, Object?>;
        expect(scored['score'], 0);
        expect(workspace.read(relative), isNot(contains(_secret)));
      }
    },
  );

  test('a missing lighthouse executable exits with the install hint', () async {
    final workspace = Workspace(root);
    workspace.write(
      'flighthouse.yaml',
      'app: quark\nweb:\n  routes: [/files]\n',
    );
    final browser = RecordingBrowser();
    final run = await workspace.execute(
      ['collect'],
      runProcess: (executable, arguments, {workingDirectory}) async {
        if (executable == 'flutter') {
          File(p.join(workingDirectory!, 'build/web/index.html'))
            ..parent.createSync(recursive: true)
            ..writeAsStringSync('app');
          return ProcessResult(1, 0, '', '');
        }
        throw const ProcessException(
          'lighthouse',
          [],
          'No such file or directory',
        );
      },
      launchBrowser: (_) async => Ok(browser.session),
      platformEnvironment: const {'FLIGHTHOUSE_PASSWORD': _secret},
    );

    expect(run.code, exitInputError);
    expect(
      run.err,
      contains(
        'Lighthouse not found. Install it with: npm install -g lighthouse',
      ),
    );
    expect(run.err, isNot(contains(_secret)));
    expect(browser.closes, 1);
    expect(
      Directory(workspace.path('.flighthouse/raw/lighthouse')).existsSync(),
      isFalse,
    );
    expect(
      Directory(workspace.path('.flighthouse/raw/axe')).existsSync(),
      isFalse,
    );
  });

  test(
    'unusable lighthouse JSON is an input error and is not stored',
    () async {
      final workspace = Workspace(root);
      workspace.write(
        'flighthouse.yaml',
        'app: quark\nweb:\n  routes: [/files]\n',
      );
      final browser = RecordingBrowser();
      final run = await workspace.execute(
        ['collect'],
        runProcess: (executable, arguments, {workingDirectory}) async {
          if (executable == 'flutter') {
            File(p.join(workingDirectory!, 'build/web/index.html'))
              ..parent.createSync(recursive: true)
              ..writeAsStringSync('app');
            return ProcessResult(1, 0, '', '');
          }
          return ProcessResult(1, 0, '{nope', '');
        },
        launchBrowser: (_) async => Ok(browser.session),
      );

      expect(run.code, exitInputError);
      expect(run.err, contains('not valid JSON'));
      expect(browser.closes, 1);
      expect(
        Directory(workspace.path('.flighthouse/raw/lighthouse')).existsSync(),
        isFalse,
      );
    },
  );

  test('report, ci, and baseline do not launch web tools', () async {
    final workspace = Workspace(root);
    workspace.write(
      'flighthouse.yaml',
      'app: quark\nweb:\n  routes: [/files]\n',
    );
    for (final arguments in [
      ['report'],
      ['ci'],
      ['baseline'],
      ['baseline', '--update'],
    ]) {
      final run = await workspace.execute(
        arguments,
        runProcess: (executable, _, {workingDirectory}) async =>
            fail('${arguments.join(' ')} spawned $executable'),
        launchBrowser: (_) async =>
            fail('${arguments.join(' ')} launched Chrome'),
      );
      expect(run.code, exitInputError, reason: arguments.join(' '));
    }
    expect(workspace.exists('flighthouse-baseline.json'), isFalse);
  });

  test('collect without web does not launch web tools', () async {
    final workspace = Workspace(root);
    workspace.write(
      'flighthouse.yaml',
      'app: quark\nsources:\n  attest:\n    dir: attest-out\n',
    );
    workspace.write('attest-out/sample.json', '{}\n');
    final run = await workspace.execute(
      ['collect'],
      runProcess: (executable, _, {workingDirectory}) async =>
          fail('collect spawned $executable'),
      launchBrowser: (_) async => fail('collect launched Chrome'),
    );
    expect(run.code, exitPassed);
    expect(workspace.read('.flighthouse/raw/attest/sample.json'), '{}\n');
  });
}

typedef Run = ({int code, String out, String err});

final class Workspace {
  Workspace(this.root);

  final Directory root;

  String path(String relative) => p.join(root.path, relative);

  void write(String relative, String contents) {
    File(path(relative))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(contents);
  }

  bool exists(String relative) => File(path(relative)).existsSync();

  String read(String relative) => File(path(relative)).readAsStringSync();

  Future<Run> execute(
    List<String> arguments, {
    required ProcessRun runProcess,
    required WebBrowserLauncher launchBrowser,
    Map<String, String>? platformEnvironment,
  }) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runCli(
      ['--config', path('flighthouse.yaml'), ...arguments],
      version: '9.9.9',
      environment: (
        now: () => DateTime.utc(2026, 10, 8),
        commitOf: (_) async => 'abc1234',
        out: out,
        err: err,
      ),
      runProcess: runProcess,
      launchBrowser: launchBrowser,
      platformEnvironment: platformEnvironment,
    );
    return (code: code, out: '$out', err: '$err');
  }
}

final class Script {
  Script(this._report);

  final String Function(List<String> arguments) _report;
  final List<({String executable, List<String> arguments})> calls = [];

  Future<ProcessResult> call(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    calls.add((executable: executable, arguments: arguments));
    if (executable == 'flutter') {
      File(p.join(workingDirectory!, 'build/web/index.html'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('app');
      return ProcessResult(1, 0, '', '');
    }
    return ProcessResult(1, 0, _report(arguments), '');
  }
}

final class RecordingBrowser {
  RecordingBrowser() {
    session = BrowserSession(
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
          url = target;
        },
        waitForFirstFrame: (_) async {},
        currentUrl: () => url.toString(),
        waitForSelector: (_, _) async {},
        click: (selector) async {
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
  final Map<String, String> values = {};
  Uri url = Uri.parse('http://127.0.0.1/');
  bool authenticated = false;
  int closes = 0;
}

String lighthouseReport(String finalUrl) => jsonEncode({
  'lighthouseVersion': '13.5.0',
  'requestedUrl': finalUrl,
  'finalDisplayedUrl': finalUrl,
  'categories': {
    'performance': _category(['performance-audit']),
    'accessibility': _category(['accessibility-audit']),
    'best-practices': _category(['best-practices-audit']),
  },
  'audits': {
    'performance-audit': _audit('performance-audit', 1, 'numeric'),
    'accessibility-audit': _audit('accessibility-audit', 0, 'binary'),
    'best-practices-audit': _audit('best-practices-audit', 1, 'binary'),
  },
});

Map<String, Object?> _category(List<String> ids) => {
  'auditRefs': [
    for (final id in ids) {'id': id, 'weight': 1},
  ],
};

Map<String, Object?> _audit(String id, Object? score, String mode) => {
  'id': id,
  'title': id,
  'score': score,
  'scoreDisplayMode': mode,
};
