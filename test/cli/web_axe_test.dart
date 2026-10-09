import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flighthouse/src/cli/cli.dart';
import 'package:flighthouse/src/io/browser.dart';
import 'package:flighthouse/src/result/result.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _secret = 's3cret-value';
const _routes = ['/files', '/photos?album=a/../../b#top'];
const _localScript = 'window.__flighthouseAxe = "local-script";';
const _pinnedScript = '/* axe-core 4.11.1 */';

const _localConfig = '''
app: quark
web:
  projectDir: app
  routes:
    - /files
    - "/photos?album=a/../../b#top"
  auth:
    url: /login
    steps:
      - type: type
        selector: "#password"
        valueFromEnv: FLIGHTHOUSE_PASSWORD
      - type: click
        selector: "#submit"
  axe:
    version: 9.9.9
    scriptPath: tools/axe.min.js
''';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('flighthouse-web-axe');
  });

  tearDown(() => root.delete(recursive: true));

  test(
    'collect injects a local script with ancestry and writes each result',
    () async {
      final workspace = Workspace(root);
      workspace.write('flighthouse.yaml', _localConfig);
      workspace.write('tools/axe.min.js', _localScript);
      workspace.write('.flighthouse/raw/axe/stale.json', '{}');
      workspace.write('.flighthouse/raw/axe/photos/escaped.json', '{}');
      final browser = RecordingBrowser();
      final downloads = <Uri>[];
      var launches = 0;

      final run = await workspace.execute(
        ['collect'],
        browser: browser,
        downloads: downloads,
        onLaunch: () => launches++,
        platformEnvironment: const {'FLIGHTHOUSE_PASSWORD': _secret},
      );

      expect(run.code, exitPassed);
      expect(run.err, isEmpty);
      expect(run.out, contains('collected 2 lighthouse files'));
      expect(run.out, contains('collected 2 axe files'));
      expect(run.out, isNot(contains(_secret)));
      expect(run.err, isNot(contains(_secret)));
      expect(downloads, isEmpty);
      expect(launches, 1);
      expect(browser.closes, 1);
      expect(browser.values['#password'], _secret);
      expect(browser.axeScripts, hasLength(_routes.length));
      expect(
        browser.axeScripts.every(
          (script) => script.contains('axe.run(document, { ancestry: true })'),
        ),
        isTrue,
      );
      expect(browser.axeArguments, everyElement([_localScript]));
      expect(browser.events.first, 'flutter');
      expect(
        browser.events.indexOf('lighthouse'),
        lessThan(browser.events.indexOf('axe')),
      );
      expect(browser.events.where((event) => event == 'flutter'), ['flutter']);
      expect(
        browser.events.where((event) => event == 'lighthouse'),
        hasLength(2),
      );
      expect(
        File(workspace.path('.flighthouse/raw/axe/stale.json')).existsSync(),
        isFalse,
      );
      expect(
        Directory(workspace.path('.flighthouse/raw/axe/photos')).existsSync(),
        isFalse,
      );
      expect(browser.axeResults, hasLength(_routes.length));
      for (var index = 0; index < _routes.length; index++) {
        final name = _artifactName(_routes[index]);
        final relative = '.flighthouse/raw/axe/$name';
        expect(name, matches(RegExp(r'^[0-9a-f]{64}\.json$')));
        expect(name, isNot(contains('photos')));
        expect(workspace.read(relative), browser.axeResults[index]);
        expect(workspace.read(relative), contains('"#action-499"'));
        expect(workspace.read(relative), contains('["iframe","#shadow"]'));
        expect(workspace.read(relative), isNot(contains(_secret)));
        final lighthouse = workspace.read('.flighthouse/raw/lighthouse/$name');
        expect(lighthouse, contains('"lighthouseVersion"'));
      }
      expect(
        Directory(workspace.path('.flighthouse/raw/axe'))
            .listSync()
            .whereType<File>(),
        hasLength(_routes.length),
      );
    },
  );

  test('collect downloads a pinned axe-core once and reuses it', () async {
    final workspace = Workspace(root);
    workspace.write(
      'flighthouse.yaml',
      'app: quark\nweb:\n  routes:\n    - /files\n    - "/photos?album=a/../../b#top"\n',
    );
    final downloads = <Uri>[];
    final firstBrowser = RecordingBrowser(result: _pinnedResult);
    final first = await workspace.execute(
      ['collect'],
      browser: firstBrowser,
      downloads: downloads,
      downloadBody: _pinnedScript,
    );
    final secondBrowser = RecordingBrowser(result: _pinnedResult);
    final second = await workspace.execute(
      ['collect'],
      browser: secondBrowser,
      downloads: downloads,
      downloadBody: 'should not download again',
    );

    expect(first.code, exitPassed, reason: first.err);
    expect(second.code, exitPassed, reason: second.err);
    expect(downloads, [
      Uri.parse(
        'https://cdnjs.cloudflare.com/ajax/libs/axe-core/4.11.1/axe.min.js',
      ),
    ]);
    expect(
      File(workspace.path('.cache/axe/4.11.1/axe.min.js')).readAsStringSync(),
      _pinnedScript,
    );
    expect(firstBrowser.axeArguments, everyElement([_pinnedScript]));
    expect(secondBrowser.axeArguments, everyElement([_pinnedScript]));
    expect(firstBrowser.closes, 1);
    expect(secondBrowser.closes, 1);
  });

  test('a failed axe download fails collection and writes no audit', () async {
    final workspace = Workspace(root);
    workspace.write(
      'flighthouse.yaml',
      'app: quark\nweb:\n  routes: [/files]\n',
    );
    final browser = RecordingBrowser();
    final downloads = <Uri>[];
    final run = await workspace.execute(
      ['collect'],
      browser: browser,
      downloads: downloads,
      downloadError: const SocketException('Connection refused'),
      platformEnvironment: const {'FLIGHTHOUSE_PASSWORD': _secret},
    );

    expect(run.code, exitInputError);
    expect(run.err, contains('could not download axe-core'));
    expect(run.err, contains('4.11.1/axe.min.js'));
    expect(run.err, contains('Connection refused'));
    expect(run.err, isNot(contains(_secret)));
    expect(run.out, isNot(contains(_secret)));
    expect(downloads, hasLength(1));
    expect(browser.closes, 1);
    expect(browser.axeScripts, isEmpty);
    expect(
      Directory(workspace.path('.flighthouse/raw/axe')).existsSync(),
      isFalse,
    );
    expect(
      File(workspace.path('.cache/axe/4.11.1/axe.min.js')).existsSync(),
      isFalse,
    );
    expect(
      workspace.exists(
        '.flighthouse/raw/lighthouse/${_artifactName('/files')}',
      ),
      isTrue,
    );
  });

  test('a route that displays a different URL fails with both paths', () async {
    final workspace = Workspace(root);
    workspace.write(
      'flighthouse.yaml',
      'app: quark\n'
          'web:\n'
          '  routes: [/files]\n'
          '  axe:\n'
          '    scriptPath: tools/axe.min.js\n',
    );
    workspace.write('tools/axe.min.js', _localScript);
    final browser = RecordingBrowser(
      relocate: (target, navigation) =>
          navigation == 1 ? target : target.replace(path: '/login'),
    );
    final run = await workspace.execute(['collect'], browser: browser);

    expect(run.code, exitInputError);
    expect(run.err, contains('/files'));
    expect(run.err, contains('/login'));
    expect(browser.closes, 1);
    expect(browser.axeScripts, isEmpty);
    expect(
      Directory(workspace.path('.flighthouse/raw/axe')).existsSync(),
      isFalse,
    );
    expect(
      workspace.exists('.flighthouse/raw/axe/${_artifactName('/files')}'),
      isFalse,
    );
    expect(
      workspace.exists('.flighthouse/raw/axe/${_artifactName('/login')}'),
      isFalse,
    );
  });

  test('report, ci, baseline, and non-web collect do not touch axe', () async {
    final workspace = Workspace(root);
    workspace.write(
      'flighthouse.yaml',
      'app: quark\nweb:\n  routes: [/files]\n',
    );
    final downloads = <Uri>[];
    var launches = 0;
    final commands = <List<String>>[];
    for (final arguments in [
      ['report'],
      ['ci'],
      ['baseline'],
      ['baseline', '--update'],
    ]) {
      final run = await workspace.execute(
        arguments,
        downloads: downloads,
        onLaunch: () => launches++,
        onProcess: (executable) =>
            commands.add([arguments.join(' '), executable]),
      );
      expect(run.code, exitInputError, reason: arguments.join(' '));
    }
    workspace.write(
      'flighthouse.yaml',
      'app: quark\nsources:\n  attest:\n    dir: attest-out\n',
    );
    workspace.write('attest-out/sample.json', '{}\n');
    final collected = await workspace.execute(
      ['collect'],
      downloads: downloads,
      onLaunch: () => launches++,
      onProcess: (executable) => commands.add(['collect', executable]),
    );

    expect(collected.code, exitPassed);
    expect(downloads, isEmpty);
    expect(launches, 0);
    expect(commands, isEmpty);
    expect(workspace.exists('flighthouse-baseline.json'), isFalse);
    expect(Directory(workspace.path('.cache/axe')).existsSync(), isFalse);
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
    RecordingBrowser? browser,
    List<Uri>? downloads,
    String? downloadBody,
    Exception? downloadError,
    void Function()? onLaunch,
    void Function(String executable)? onProcess,
    Map<String, String>? platformEnvironment,
  }) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final session = browser ?? RecordingBrowser();
    final code = await runCli(
      ['--config', path('flighthouse.yaml'), ...arguments],
      version: '9.9.9',
      environment: (
        now: () => DateTime.utc(2026, 10, 8),
        commitOf: (_) async => 'abc1234',
        out: out,
        err: err,
      ),
      runProcess: (executable, processArguments, {workingDirectory}) async {
        onProcess?.call(executable);
        session.events.add(executable);
        if (executable == 'flutter') {
          File(p.join(workingDirectory!, 'build/web/index.html'))
            ..parent.createSync(recursive: true)
            ..writeAsStringSync('app');
          return ProcessResult(1, 0, '', '');
        }
        final url = processArguments.cast<String>().firstWhere(
          (argument) => argument.startsWith('http://'),
          orElse: () => '',
        );
        return ProcessResult(1, 0, _lighthouseReport(url), '');
      },
      launchBrowser: (_) async {
        onLaunch?.call();
        session.events.add('launch');
        return Ok(session.session);
      },
      platformEnvironment: platformEnvironment,
      downloadAxe: (url) async {
        downloads?.add(url);
        if (downloadError != null) throw downloadError;
        return downloadBody ?? _pinnedScript;
      },
      axeCacheDir: path('.cache/axe'),
    );
    return (code: code, out: '$out', err: '$err');
  }
}

final class RecordingBrowser {
  RecordingBrowser({this.relocate, this.result = largeAxeResult});

  final Uri Function(Uri target, int navigation)? relocate;
  final String Function(String pageUrl) result;
  final List<String> events = [];
  final List<String> axeScripts = [];
  final List<List<Object?>> axeArguments = [];
  final List<String> axeResults = [];
  final Map<String, String> values = {};
  int navigations = 0;
  int closes = 0;
  Uri url = Uri.parse('http://127.0.0.1/');

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
        navigations += 1;
        url = relocate?.call(target, navigations) ?? target;
      },
      waitForFirstFrame: (_) async {},
      currentUrl: () => url.toString(),
      waitForSelector: (_, _) async {},
      click: (selector) async {
        if (selector == '#submit') events.add('submit');
      },
      focus: (_) async {},
      waitForFocus: (_, _) async {},
      settleInput: () async {},
      replaceInput: (selector, value) async {
        values[selector] = value;
      },
      readInput: (selector) async => values[selector],
      evaluate: (script, arguments) async {
        if (!script.contains('axe.run')) return 4;
        events.add('axe');
        axeScripts.add(script);
        axeArguments.add(arguments);
        final raw = result(url.toString());
        axeResults.add(raw);
        return raw;
      },
      close: () async {
        closes++;
      },
    ),
  );
}

String _artifactName(String route) =>
    '${sha256.convert(utf8.encode(route))}.json';

String _pinnedResult(String pageUrl) => jsonEncode({
  'testEngine': {'name': 'axe-core', 'version': '4.11.1'},
  'url': pageUrl,
  'violations': <Object?>[],
  'passes': <Object?>[],
  'incomplete': <Object?>[],
  'inapplicable': <Object?>[],
});

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

String _lighthouseReport(String finalUrl) => jsonEncode({
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
