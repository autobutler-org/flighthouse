import 'dart:io';

import 'package:flighthouse/src/cli/cli.dart';
import 'package:flighthouse/src/result/failure.dart';
import 'package:flighthouse/src/result/result.dart';
import 'package:test/test.dart';

import 'web_lighthouse_test.dart'
    show RecordingBrowser, Run, Script, Workspace, lighthouseReport;

const _username = 'audit-user-5d2b';
const _password = 'p4ss-9c1e';
const _envPassword = 'env-pass-77aa';

const _hosts =
    '''
hosts:
  https://app.example.com:
    username: $_username
    password: $_password
''';

const _twoHosts =
    '''
$_hosts  http://127.0.0.1:8080:
    username: local
    password: local-pass
''';

String _config(String steps) =>
    '''
app: example
web:
  projectDir: app
  build:
    command: [flutter, build, web, --release]
    outputDir: build/web
  routes: [/files]
  auth:
    url: /login
    steps:
$steps
      - type: click
        selector: "#submit"
  lighthouse:
    command: [lighthouse]
  axe:
    scriptPath: tools/axe.min.js
''';

final _hostSteps = _config('''
      - type: type
        selector: "#host"
        valueFromHost: url
      - type: type
        selector: "#username"
        valueFromHost: username
      - type: type
        selector: "#password"
        valueFromHost: password
        valueFromEnv: FLIGHTHOUSE_PASSWORD''');

final _envSteps = _config('''
      - type: type
        selector: "#password"
        valueFromEnv: FLIGHTHOUSE_PASSWORD''');

void main() {
  late Directory root;
  late Workspace workspace;
  late RecordingBrowser browser;
  late Script script;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('flighthouse-web-hosts');
    workspace = Workspace(root)..write('tools/axe.min.js', 'local axe script');
    browser = RecordingBrowser();
    script = Script(
      (arguments) => lighthouseReport(
        arguments.firstWhere((argument) => argument.startsWith('http://')),
      ),
    );
  });

  tearDown(() => root.delete(recursive: true));

  Future<Run> collect(
    List<String> arguments, {
    Map<String, String> environment = const {},
    HostsFileRead? readHostsFile,
  }) => workspace.execute(
    ['collect', ...arguments],
    runProcess: script.call,
    launchBrowser: (_) async => Ok(browser.session),
    platformEnvironment: environment,
    readHostsFile: readHostsFile,
  );

  void expectNoCredentials(Run run) {
    final written = [
      for (final entity in root.listSync(recursive: true))
        if (entity is File && !entity.path.endsWith('hosts.yaml'))
          entity.readAsStringSync(),
    ];
    for (final text in [
      run.out,
      run.err,
      ...written,
      for (final call in script.calls) call.arguments.join('\n'),
    ]) {
      expect(text, isNot(contains(_password)));
      expect(text, isNot(contains(_username)));
    }
  }

  test('collect --host types the entry read beside the config', () async {
    workspace.write('flighthouse.yaml', _hostSteps);
    final paths = <String>[];
    final run = await collect(
      ['--host', 'https://app.example.com'],
      environment: const {'FLIGHTHOUSE_PASSWORD': _envPassword},
      readHostsFile: (path) async {
        paths.add(path);
        return const Ok(_twoHosts);
      },
    );

    expect(run.err, isEmpty);
    expect(run.code, exitPassed);
    expect(paths, [workspace.path('.flighthouse/hosts.yaml')]);
    expect(browser.values, {
      '#host': 'https://app.example.com',
      '#username': _username,
      '#password': _password,
    });
    expectNoCredentials(run);
  });

  test(
    'the only entry of the real hosts file is used without --host',
    () async {
      workspace
        ..write('flighthouse.yaml', _hostSteps)
        ..write('.flighthouse/hosts.yaml', _hosts);
      final run = await collect([]);

      expect(run.err, isEmpty);
      expect(run.code, exitPassed);
      expect(browser.values['#password'], _password);
      expectNoCredentials(run);
    },
  );

  test('an environment-only config never reads the hosts file', () async {
    workspace
      ..write('flighthouse.yaml', _envSteps)
      ..write('.flighthouse/hosts.yaml', 'hosts: [not, a, mapping');
    final run = await collect(
      [],
      environment: const {'FLIGHTHOUSE_PASSWORD': _envPassword},
      readHostsFile: (path) async => fail('collect read $path'),
    );

    expect(run.err, isEmpty);
    expect(run.code, exitPassed);
    expect(browser.values, {'#password': _envPassword});
  });

  test('several entries and no --host fail before sign-in', () async {
    workspace.write('flighthouse.yaml', _hostSteps);
    final run = await collect(
      [],
      environment: const {'FLIGHTHOUSE_PASSWORD': _envPassword},
      readHostsFile: (_) async => const Ok(_twoHosts),
    );

    expect(run.code, exitInputError);
    expect(
      run.err,
      contains(
        'could not read web authentication credential '
        'web.auth.steps[0].valueFromHost (url): no host is selected; pass '
        '--host; defined hosts: https://app.example.com, http://127.0.0.1:8080',
      ),
    );
    expect(browser.values, isEmpty);
    expectNoCredentials(run);
  });

  test('no hosts file and no fallback names the file', () async {
    workspace.write('flighthouse.yaml', _hostSteps);
    final run = await collect([]);

    expect(run.code, exitInputError);
    expect(run.err, contains('no host is selected'));
    expect(
      run.err,
      contains('${workspace.path('.flighthouse/hosts.yaml')} was not found'),
    );
  });

  test('--host with no hosts file fails before any tool runs', () async {
    workspace.write('flighthouse.yaml', _envSteps);
    final run = await collect(['--host', 'https://app.example.com']);

    expect(run.code, exitInputError);
    expect(
      run.err,
      contains(
        'could not read ${workspace.path('.flighthouse/hosts.yaml')}: '
        'not found; --host needs an entry under hosts in this file',
      ),
    );
    expect(script.calls, isEmpty);
  });

  test('--host naming an absent entry lists the defined hosts', () async {
    workspace.write('flighthouse.yaml', _hostSteps);
    final run = await collect([
      '--host',
      'https://other.example.com',
    ], readHostsFile: (_) async => const Ok(_twoHosts));

    expect(run.code, exitInputError);
    expect(
      run.err,
      contains(
        'could not select host https://other.example.com: no entry in '
        '${workspace.path('.flighthouse/hosts.yaml')}; defined hosts: '
        'https://app.example.com, http://127.0.0.1:8080',
      ),
    );
    expect(script.calls, isEmpty);
    expectNoCredentials(run);
  });

  test('an entry without a password names the file and the path', () async {
    workspace.write('flighthouse.yaml', _hostSteps);
    final run = await collect(
      [],
      readHostsFile: (_) async => const Ok(
        'hosts:\n  https://app.example.com:\n    username: $_username\n',
      ),
    );

    expect(run.code, exitUsageError);
    expect(
      run.err,
      contains(
        'config: ${workspace.path('.flighthouse/hosts.yaml')}: '
        'hosts.https://app.example.com.password (line 3, column 5): '
        'is required',
      ),
    );
    expectNoCredentials(run);
  });

  test('an unreadable hosts file is reported as it is', () async {
    workspace.write('flighthouse.yaml', _hostSteps);
    final run = await collect(
      [],
      readHostsFile: (path) async => Err(
        IoFailure(operation: 'read', path: path, reason: 'Permission denied'),
      ),
    );

    expect(run.code, exitInputError);
    expect(run.err, contains('hosts.yaml: Permission denied'));
    expect(script.calls, isEmpty);
  });

  test('collect --help describes --host', () {
    expect(
      () => runCli(['collect', '--help'], version: '9.9.9'),
      prints(
        allOf(
          contains('--host=<url>'),
          contains('.flighthouse/hosts.yaml'),
          contains('valueFromHost'),
        ),
      ),
    );
  });
}
