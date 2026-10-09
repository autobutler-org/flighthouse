import 'dart:convert';
import 'dart:io';

import 'package:flighthouse/src/cli/cli.dart';
import 'package:flighthouse/src/render/html_renderer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const fixtureRoot = 'test/fixtures';

typedef QuarkRun = Future<({int code, String out, String err})> Function(
  List<String> arguments,
);

typedef QuarkWorkspace = ({
  QuarkRun run,
  String baselinePath,
  String reportDir,
});

void main() {
  group('phase 1 quark 48a76ae', () {
    const quarkCommit = '48a76ae';
    late QuarkWorkspace workspace;
    setUp(() async {
      workspace = await _workspace(
        commit: quarkCommit,
        timestamp: DateTime.utc(2026, 10, 8),
        sources: {
          'attest': 'attest/1.5.0/quark-$quarkCommit',
          'lighthouse': 'lighthouse/13.5.0/quark-$quarkCommit',
        },
      );
    });
    tearDown(
      () => Directory(p.dirname(workspace.reportDir)).delete(recursive: true),
    );

    test(
      'real quark reports merge, render, and pass an unchanged baseline',
      () async {
        final collect = await workspace.run(['collect']);
        expect(collect.code, exitPassed);
        expect(
          collect.out,
          'collected 8 attest files\ncollected 4 lighthouse files\n',
        );
        expect((await workspace.run(['report'])).code, exitPassed);
        expect(
          (await workspace.run(['baseline', '--update'])).code,
          exitPassed,
        );
        final ci = await workspace.run(['ci']);
        expect(ci.code, exitPassed);
        expect(ci.err, isEmpty);
        expect(ci.out, contains('overall 81 | a11y 94 | perf 69'));
        expect(ci.out, contains('0 new, 0 fixed, 71 unchanged'));
        expect(ci.out, endsWith('gate passed\n'));
        final report = jsonDecode(
          await File(p.join(workspace.reportDir, 'report.json')).readAsString(),
        ) as Map<String, Object?>;
        expect(report['metadata'], {
          'app': 'quark',
          'commit': quarkCommit,
          'timestamp': '2026-10-08T00:00:00.000Z',
          'flighthouseVersion': '0.1.0',
          'toolVersions': {'attest': '1.5.0', 'lighthouse': '13.5.0'},
        });
        final html = await File(p.join(workspace.reportDir, 'report.html'))
            .readAsString();
        expect(html, startsWith('<!doctype html>'));
        expect(html, contains(escapeHtml('/recover/narrow')));
        expect(html, contains(escapeHtml('attest/contrast')));
      },
    );

    test(
      'adding a recorded quark screen fails on its real new findings',
      () async {
        expect((await workspace.run(['collect'])).code, exitPassed);
        await File(
          p.join(workspace.reportDir, 'raw', 'attest', 'recover-narrow.json'),
        ).delete();
        expect(
          (await workspace.run(['baseline', '--update'])).code,
          exitPassed,
        );
        final previousBaseline = await File(workspace.baselinePath)
            .readAsString();
        expect((await workspace.run(['collect'])).code, exitPassed);
        final ci = await workspace.run(['ci']);
        expect(ci.code, exitGateFailed);
        expect(ci.err, contains('new serious a11y finding on /recover/narrow'));
        expect(ci.out, endsWith('gate failed\n'));
        expect(
          await File(workspace.baselinePath).readAsString(),
          previousBaseline,
        );
        expect(
          await File(p.join(workspace.reportDir, 'report.html')).readAsString(),
          contains('class="badge new"'),
        );
      },
    );

    test(
      'unusable input cannot pass the gate or replace a quark baseline',
      () async {
        expect((await workspace.run(['collect'])).code, exitPassed);
        expect(
          (await workspace.run(['baseline', '--update'])).code,
          exitPassed,
        );
        final previousBaseline = await File(workspace.baselinePath)
            .readAsString();
        await File(p.join(workspace.reportDir, 'raw', 'attest', 'corrupt.json'))
            .writeAsBytes([0xff]);
        final ci = await workspace.run(['ci']);
        expect(ci.code, exitInputError);
        expect(ci.err, contains('the gate was not evaluated'));
        expect(ci.err, contains('corrupt.json'));
        expect(ci.out, isNot(contains('gate passed')));
        final baseline = await workspace.run(['baseline', '--update']);
        expect(baseline.code, exitInputError);
        expect(baseline.err, contains('the baseline was not touched'));
        expect(
          await File(workspace.baselinePath).readAsString(),
          previousBaseline,
        );
      },
    );
  });

  group('phase 2 authenticated quark d8d2618e web collection', () {
    const quarkCommit = 'd8d2618e';
    late QuarkWorkspace workspace;
    setUp(() async {
      workspace = await _workspace(
        commit: quarkCommit,
        timestamp: DateTime.utc(2026, 10, 9),
        sources: {
          'lighthouse': 'lighthouse/13.5.0/quark-$quarkCommit',
          'axe': 'axe/4.11.1/quark-$quarkCommit',
        },
      );
    });
    tearDown(
      () => Directory(p.dirname(workspace.reportDir)).delete(recursive: true),
    );

    test('recorded authenticated routes pass an unchanged baseline', () async {
      final collect = await workspace.run(['collect']);
      expect(collect.code, exitPassed);
      expect(
        collect.out,
        'collected 3 lighthouse files\ncollected 3 axe files\n',
      );
      expect((await workspace.run(['report'])).code, exitPassed);
      expect((await workspace.run(['baseline', '--update'])).code, exitPassed);
      final ci = await workspace.run(['ci']);
      expect(ci.code, exitPassed);
      expect(ci.err, isEmpty);
      expect(
        ci.out,
        contains('overall 74 | a11y 88 | perf 58 | responsiveness n/a'),
      );
      expect(ci.out, contains('0 new, 0 fixed, 157 unchanged'));
      expect(ci.out, endsWith('gate passed\n'));
      final report = jsonDecode(
        await File(p.join(workspace.reportDir, 'report.json')).readAsString(),
      ) as Map<String, Object?>;
      expect(report['metadata'], {
        'app': 'quark',
        'commit': quarkCommit,
        'timestamp': '2026-10-09T00:00:00.000Z',
        'flighthouseVersion': '0.1.0',
        'toolVersions': {'lighthouse': '13.5.0', 'axe': '4.11.1'},
      });
      final routes = {
        for (final finding in report['findings']! as List<Object?>)
          (finding! as Map<String, Object?>)['route'],
      };
      expect(routes, {'/files', '/photos', '/settings/general'});
    });

    test('the recorded gallery fails the gate when it is new', () async {
      expect((await workspace.run(['collect'])).code, exitPassed);
      await File(
        p.join(workspace.reportDir, 'raw', 'axe', '$_photosRouteHash.json'),
      ).delete();
      expect((await workspace.run(['baseline', '--update'])).code, exitPassed);
      final previousBaseline = await File(workspace.baselinePath)
          .readAsString();
      expect((await workspace.run(['collect'])).code, exitPassed);
      final ci = await workspace.run(['ci']);
      expect(ci.code, exitGateFailed);
      expect(
        ci.err,
        contains('new serious a11y finding on /photos: nested-interactive'),
      );
      expect(ci.err, contains('aria-label="photo-01.jpg"'));
      expect(ci.out, endsWith('gate failed\n'));
      expect(
        await File(workspace.baselinePath).readAsString(),
        previousBaseline,
      );
    });

    test(
      'unusable axe input cannot pass the gate or replace the baseline',
      () async {
        expect((await workspace.run(['collect'])).code, exitPassed);
        expect(
          (await workspace.run(['baseline', '--update'])).code,
          exitPassed,
        );
        final previousBaseline = await File(workspace.baselinePath)
            .readAsString();
        await File(p.join(workspace.reportDir, 'raw', 'axe', 'corrupt.json'))
            .writeAsBytes([0xff]);
        final ci = await workspace.run(['ci']);
        expect(ci.code, exitInputError);
        expect(ci.err, contains('the gate was not evaluated'));
        expect(ci.err, contains('corrupt.json'));
        expect(ci.out, isNot(contains('gate passed')));
        final baseline = await workspace.run(['baseline', '--update']);
        expect(baseline.code, exitInputError);
        expect(baseline.err, contains('the baseline was not touched'));
        expect(
          await File(workspace.baselinePath).readAsString(),
          previousBaseline,
        );
      },
    );
  });
}

const _photosRouteHash =
    '407dd20b96399e2729553194fc85ba78c1a17899cee99bffd6e7ed6b4399a728';

Future<QuarkWorkspace> _workspace({
  required String commit,
  required DateTime timestamp,
  required Map<String, String> sources,
}) async {
  final directory = await Directory.systemTemp.createTemp('flighthouse-quark');
  final configPath = p.join(directory.path, 'flighthouse.yaml');
  final baselinePath = p.join(directory.path, 'baseline.json');
  final reportDir = p.join(directory.path, 'report');
  await File(configPath).writeAsString(
    jsonEncode({
      'app': 'quark',
      'reportDir': reportDir,
      'baseline': baselinePath,
      'sources': {
        for (final MapEntry(:key, :value) in sources.entries)
          key: {'dir': p.absolute('$fixtureRoot/$value')},
      },
    }),
  );
  Future<({int code, String out, String err})> run(
    List<String> arguments,
  ) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runCli(
      ['--config', configPath, ...arguments],
      version: '0.1.0',
      environment: (
        now: () => timestamp,
        commitOf: (_) async => commit,
        out: out,
        err: err,
      ),
    );
    return (code: code, out: '$out', err: '$err');
  }

  return (run: run, baselinePath: baselinePath, reportDir: reportDir);
}
