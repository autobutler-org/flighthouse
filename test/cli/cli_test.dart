import 'dart:convert';
import 'dart:io';

import 'package:flighthouse/src/cli/cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const lighthouseFixtures = 'test/fixtures/lighthouse/13.5.0';

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

  void copyFixture(String name, String toRelative) =>
      write(toRelative, File('$lighthouseFixtures/$name').readAsStringSync());

  bool exists(String relative) => File(path(relative)).existsSync();

  String read(String relative) => File(path(relative)).readAsStringSync();

  Future<Run> run(List<String> arguments) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runCli(
      ['--config', path('flighthouse.yaml'), ...arguments],
      version: '9.9.9',
      environment: (
        now: () => DateTime.utc(2026, 10, 6, 12),
        commitOf: (_) async => 'abc1234',
        out: out,
        err: err,
      ),
    );
    return (code: code, out: '$out', err: '$err');
  }
}

const lighthouseConfig = '''
app: quark
sources:
  lighthouse:
    dir: lh
''';

Map<String, Object?> withRequestedUrl(String fixture, String url) {
  final json = jsonDecode(
    File('$lighthouseFixtures/$fixture').readAsStringSync(),
  ) as Map<String, Object?>;
  return {...json, 'requestedUrl': url};
}

void main() {
  late Workspace workspace;

  setUp(() async {
    workspace = Workspace(await Directory.systemTemp.createTemp('flighthouse'));
    workspace.write('flighthouse.yaml', lighthouseConfig);
    workspace.copyFixture('quark-login.json', 'lh/login.json');
  });

  tearDown(() => workspace.root.delete(recursive: true));

  test('--version prints the version', () async {
    final out = StringBuffer();
    final code = await runCli(
      ['--version'],
      version: '9.9.9',
      environment: (
        now: DateTime.now,
        commitOf: (_) async => null,
        out: out,
        err: StringBuffer(),
      ),
    );
    expect(code, exitPassed);
    expect('$out', 'flighthouse 9.9.9\n');
  });

  test('an unknown command is a usage error', () async {
    final run = await workspace.run(['frobnicate']);
    expect(run.code, exitUsageError);
    expect(run.err, contains('Could not find a command named "frobnicate"'));
  });

  for (final command in ['collect', 'report', 'ci', 'baseline']) {
    test(
      '$command rejects positional arguments before changing files',
      () async {
        await workspace.run(['collect']);
        await workspace.run(['baseline', '--update']);
        workspace.copyFixture(
          'quark-login.json',
          '.flighthouse/raw/lighthouse/stale.json',
        );
        final raw = workspace.read('.flighthouse/raw/lighthouse/stale.json');
        workspace.write('.flighthouse/report.json', 'previous JSON report');
        workspace.write('.flighthouse/report.html', 'previous HTML report');
        final baseline = workspace.read('flighthouse-baseline.json');
        final run = await workspace.run([command, 'unexpected.json']);
        expect(run.code, exitUsageError);
        expect(run.err, contains('Unexpected positional arguments'));
        expect(run.err, contains('unexpected.json'));
        expect(run.out, isEmpty);
        expect(workspace.read('.flighthouse/raw/lighthouse/stale.json'), raw);
        expect(
          workspace.read('.flighthouse/report.json'),
          'previous JSON report',
        );
        expect(
          workspace.read('.flighthouse/report.html'),
          'previous HTML report',
        );
        expect(workspace.read('flighthouse-baseline.json'), baseline);
      },
    );
  }

  test(
    'baseline update with an unexpected path preserves the baseline',
    () async {
      await workspace.run(['collect']);
      await workspace.run(['baseline', '--update']);
      final baseline = workspace.read('flighthouse-baseline.json');
      workspace.copyFixture('a11y-failures.json', 'lh/login.json');
      await workspace.run(['collect']);
      final run = await workspace.run([
        'baseline',
        '--update',
        'alternative-baseline.json',
      ]);
      expect(run.code, exitUsageError);
      expect(run.err, contains('Unexpected positional arguments'));
      expect(run.err, contains('alternative-baseline.json'));
      expect(run.out, isEmpty);
      expect(workspace.read('flighthouse-baseline.json'), baseline);
      expect(workspace.exists('alternative-baseline.json'), isFalse);
    },
  );

  test('a missing config file is a config error', () async {
    File(workspace.path('flighthouse.yaml')).deleteSync();
    final run = await workspace.run(['report']);
    expect(run.code, exitUsageError);
    expect(run.err, contains('config: (file): could not read'));
  });

  test('an invalid config names the key and exits 2', () async {
    workspace.write('flighthouse.yaml', 'app: quark\ngate:\n  minSeverty: x\n');
    final run = await workspace.run(['report']);
    expect(run.code, exitUsageError);
    expect(run.err, contains('config: gate.minSeverty (line 3, column 3)'));
  });

  test('collect with no sources is a config error', () async {
    workspace.write('flighthouse.yaml', 'app: quark\n');
    workspace.write('.flighthouse/raw/lighthouse/previous.json', '{}');
    final run = await workspace.run(['collect']);
    expect(run.code, exitUsageError);
    expect(run.err, contains('configure at least one input'));
    expect(workspace.read('.flighthouse/raw/lighthouse/previous.json'), '{}');
  });

  test('report with no sources preserves existing reports', () async {
    workspace.write('flighthouse.yaml', 'app: quark\n');
    workspace.write('.flighthouse/report.json', 'previous json');
    workspace.write('.flighthouse/report.html', 'previous html');
    final run = await workspace.run(['report']);
    expect(run.code, exitUsageError);
    expect(run.err, contains('configure at least one input'));
    expect(workspace.read('.flighthouse/report.json'), 'previous json');
    expect(workspace.read('.flighthouse/report.html'), 'previous html');
  });

  test('ci with no sources preserves reports and does not pass', () async {
    workspace.write('flighthouse.yaml', 'app: quark\n');
    workspace.write(
      'flighthouse-baseline.json',
      jsonEncode({
        'schemaVersion': 1,
        'fingerprintVersion': 'v1',
        'scores': {
          'overall': null,
          'categories': {
            'a11y': null,
            'perf': null,
            'responsiveness': null,
            'memory': null,
            'best-practices': null,
          },
        },
        'findings': <Object?>[],
      }),
    );
    final baseline = workspace.read('flighthouse-baseline.json');
    workspace.write('.flighthouse/report.json', 'previous json');
    workspace.write('.flighthouse/report.html', 'previous html');
    final run = await workspace.run(['ci']);
    expect(run.code, exitUsageError);
    expect(run.err, contains('configure at least one input'));
    expect(run.out, isNot(contains('gate passed')));
    expect(workspace.read('.flighthouse/report.json'), 'previous json');
    expect(workspace.read('.flighthouse/report.html'), 'previous html');
    expect(workspace.read('flighthouse-baseline.json'), baseline);
  });

  test('baseline with no sources preserves the existing baseline', () async {
    await workspace.run(['collect']);
    await workspace.run(['baseline', '--update']);
    final baseline = workspace.read('flighthouse-baseline.json');
    workspace.write('flighthouse.yaml', 'app: quark\n');
    final run = await workspace.run(['baseline']);
    expect(run.code, exitUsageError);
    expect(run.err, contains('configure at least one input'));
    expect(workspace.read('flighthouse-baseline.json'), baseline);
  });

  test('baseline update with no sources preserves the baseline', () async {
    await workspace.run(['collect']);
    await workspace.run(['baseline', '--update']);
    final baseline = workspace.read('flighthouse-baseline.json');
    workspace.write('flighthouse.yaml', 'app: quark\n');
    final run = await workspace.run(['baseline', '--update']);
    expect(run.code, exitUsageError);
    expect(run.err, contains('configure at least one input'));
    expect(workspace.read('flighthouse-baseline.json'), baseline);
  });

  for (final arguments in [
    ['ci'],
    ['baseline', '--update'],
  ]) {
    test('${arguments.join(' ')} refuses weighted audit errors', () async {
      final json = jsonDecode(
        File('$lighthouseFixtures/audit-errors/weighted-error.json')
            .readAsStringSync(),
      ) as Map<String, Object?>;
      final categories = json['categories']! as Map<String, Object?>;
      final category = categories['accessibility']! as Map<String, Object?>;
      final refs = category['auditRefs']! as List<Object?>;
      final ref = refs.cast<Map<String, Object?>>().singleWhere(
        (ref) => ref['id'] == 'flighthouse-test-audit-error',
      );
      ref['weight'] = 0;
      workspace.write('lh/login.json', jsonEncode(json));
      await workspace.run(['collect']);
      final initial = await workspace.run(['baseline', '--update']);
      expect(initial.code, exitPassed);
      final baseline = workspace.read('flighthouse-baseline.json');
      workspace.copyFixture(
        'audit-errors/weighted-error.json',
        'lh/login.json',
      );
      await workspace.run(['collect']);
      final run = await workspace.run(arguments);
      expect(run.code, exitInputError);
      expect(run.err, contains('flighthouse-test-audit-error failed'));
      expect(run.out, isNot(contains('gate passed')));
      expect(workspace.read('flighthouse-baseline.json'), baseline);
    });
  }

  test('collect replaces earlier raw outputs', () async {
    workspace.write('.flighthouse/raw/lighthouse/stale.json', '{}');
    final run = await workspace.run(['collect']);
    expect(run.code, exitPassed);
    expect(run.out, 'collected 1 lighthouse file\n');
    expect(workspace.exists('.flighthouse/raw/lighthouse/login.json'), isTrue);
    expect(workspace.exists('.flighthouse/raw/lighthouse/stale.json'), isFalse);
  });

  test('collect from a missing directory is an input error', () async {
    File(workspace.path('lh/login.json')).deleteSync();
    Directory(workspace.path('lh')).deleteSync();
    final run = await workspace.run(['collect']);
    expect(run.code, exitInputError);
    expect(run.err, contains('could not list'));
  });

  test('report before collect says to collect first', () async {
    final run = await workspace.run(['report']);
    expect(run.code, exitInputError);
    expect(run.err, contains('run flighthouse collect first'));
  });

  test('report writes both files with the injected clock and commit', () async {
    await workspace.run(['collect']);
    final run = await workspace.run(['report']);
    expect(run.code, exitPassed);
    expect(
      run.out,
      startsWith(
        'quark: overall 80 | a11y 100 | perf 60 | responsiveness n/a | '
        'memory n/a | best-practices 77\n',
      ),
    );
    final report = jsonDecode(
      workspace.read('.flighthouse/report.json'),
    ) as Map<String, Object?>;
    expect(report['metadata'], {
      'app': 'quark',
      'commit': 'abc1234',
      'timestamp': '2026-10-06T12:00:00.000Z',
      'flighthouseVersion': '9.9.9',
      'toolVersions': {'lighthouse': '13.5.0'},
    });
    expect(
      workspace.read('.flighthouse/report.html'),
      startsWith('<!doctype html>'),
    );
  });

  test('--report-dir overrides the configured directory', () async {
    final elsewhere = workspace.path('elsewhere');
    await workspace.run(['--report-dir', elsewhere, 'collect']);
    final run = await workspace.run(['--report-dir', elsewhere, 'report']);
    expect(run.code, exitPassed);
    expect(workspace.exists('elsewhere/report.json'), isTrue);
    expect(workspace.exists('.flighthouse/report.json'), isFalse);
  });

  test(
    'a source without an adapter is reported, not silently skipped',
    () async {
      workspace.write(
        'flighthouse.yaml',
        '$lighthouseConfig  axe:\n    dir: axe\n',
      );
      workspace.write('axe/results.json', '{}');
      await workspace.run(['collect']);
      final run = await workspace.run(['report']);
      expect(run.code, exitInputError);
      expect(run.err, contains('flighthouse cannot read axe output yet'));
      expect(workspace.exists('.flighthouse/report.json'), isTrue);
    },
  );

  group('ci', () {
    setUp(() => workspace.run(['collect']));

    test('without a baseline says how to make one', () async {
      final run = await workspace.run(['ci']);
      expect(run.code, exitInputError);
      expect(
        run.err,
        contains('not found. Run: flighthouse baseline --update'),
      );
    });

    test('passes against a fresh baseline', () async {
      final update = await workspace.run(['baseline', '--update']);
      expect(update.code, exitPassed);
      expect(update.out, contains('with 18 findings'));
      final run = await workspace.run(['ci']);
      expect(run.code, exitPassed);
      expect(run.out, contains('0 new, 0 fixed, 18 unchanged'));
      expect(run.out, endsWith('gate passed\n'));
    });

    test('fails on a new page with new findings', () async {
      await workspace.run(['baseline', '--update']);
      workspace.write(
        'lh/broken.json',
        jsonEncode(
          withRequestedUrl(
            'a11y-failures.json',
            'http://127.0.0.1:8765/signup',
          ),
        ),
      );
      await workspace.run(['collect']);
      final run = await workspace.run(['ci']);
      expect(run.code, exitGateFailed);
      expect(
        run.err,
        contains('FAIL new critical a11y finding on /signup: button-name:'),
      );
      expect(run.err, contains('FAIL a11y score dropped from 100.0 to'));
      expect(run.out, endsWith('gate failed\n'));
      expect(
        workspace.read('.flighthouse/report.html'),
        contains('class="badge new"'),
      );
    });

    test('a fixed finding passes and suggests updating', () async {
      workspace.write(
        'flighthouse.yaml',
        '${lighthouseConfig}gate:\n  maxScoreDrop: {overall: 100, a11y: 100, '
            'perf: 100, best-practices: 100}\n',
      );
      workspace.write(
        'lh/broken.json',
        jsonEncode(
          withRequestedUrl(
            'a11y-failures.json',
            'http://127.0.0.1:8765/signup',
          ),
        ),
      );
      await workspace.run(['collect']);
      await workspace.run(['baseline', '--update']);
      File(workspace.path('lh/broken.json')).deleteSync();
      await workspace.run(['collect']);
      final run = await workspace.run(['ci']);
      expect(run.code, exitPassed);
      expect(run.out, contains('fixed; run flighthouse baseline --update'));
    });

    test('refuses a baseline from another fingerprint scheme', () async {
      await workspace.run(['baseline', '--update']);
      final baseline = jsonDecode(
        workspace.read('flighthouse-baseline.json'),
      ) as Map<String, Object?>;
      workspace.write(
        'flighthouse-baseline.json',
        jsonEncode({...baseline, 'fingerprintVersion': 'v0'}),
      );
      final run = await workspace.run(['ci']);
      expect(run.code, exitInputError);
      expect(run.err, contains('it uses fingerprint scheme v0'));
    });

    test('a corrupt baseline is an input error', () async {
      workspace.write('flighthouse-baseline.json', '{not json');
      final run = await workspace.run(['ci']);
      expect(run.code, exitInputError);
      expect(run.err, contains('not valid JSON'));
    });

    test('does not evaluate the gate on unusable input', () async {
      await workspace.run(['baseline', '--update']);
      workspace.write('.flighthouse/raw/lighthouse/bad.json', '{nope');
      final run = await workspace.run(['ci']);
      expect(run.code, exitInputError);
      expect(run.err, contains('the gate was not evaluated'));
    });
  });

  group('baseline', () {
    setUp(() => workspace.run(['collect']));

    test('without --update and no baseline says how to make one', () async {
      final run = await workspace.run(['baseline']);
      expect(run.code, exitPassed);
      expect(run.out, contains('no baseline at'));
      expect(workspace.exists('flighthouse-baseline.json'), isFalse);
    });

    test(
      '--update writes a canonical file that regenerates identically',
      () async {
        await workspace.run(['baseline', '--update']);
        final first = workspace.read('flighthouse-baseline.json');
        await workspace.run(['baseline', '--update']);
        expect(workspace.read('flighthouse-baseline.json'), first);
        expect(first, endsWith('}\n'));
      },
    );

    test('--update refuses to write from unusable input', () async {
      workspace.write('.flighthouse/raw/lighthouse/bad.json', '{nope');
      final run = await workspace.run(['baseline', '--update']);
      expect(run.code, exitInputError);
      expect(run.err, contains('the baseline was not touched'));
      expect(workspace.exists('flighthouse-baseline.json'), isFalse);
    });
  });
}
