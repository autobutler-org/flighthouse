import 'dart:convert';
import 'dart:io';

import 'package:flighthouse/src/cli/cli.dart';
import 'package:flighthouse/src/render/html_renderer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const quarkCommit = '48a76ae';
const fixtureRoot = 'test/fixtures';

void main() {
  late Directory workspace;
  late String configPath;
  late String baselinePath;
  late String reportDir;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('flighthouse-quark');
    configPath = p.join(workspace.path, 'flighthouse.yaml');
    baselinePath = p.join(workspace.path, 'baseline.json');
    reportDir = p.join(workspace.path, 'report');
    await File(configPath).writeAsString(
      jsonEncode({
        'app': 'quark',
        'reportDir': reportDir,
        'baseline': baselinePath,
        'sources': {
          'attest': {
            'dir': p.absolute('$fixtureRoot/attest/1.5.0/quark-$quarkCommit'),
          },
          'lighthouse': {
            'dir': p.absolute(
              '$fixtureRoot/lighthouse/13.5.0/quark-$quarkCommit',
            ),
          },
        },
      }),
    );
  });
  tearDown(() => workspace.delete(recursive: true));

  Future<({int code, String out, String err})> run(
    List<String> arguments,
  ) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runCli(
      ['--config', configPath, ...arguments],
      version: '0.1.0',
      environment: (
        now: () => DateTime.utc(2026, 10, 8),
        commitOf: (_) async => quarkCommit,
        out: out,
        err: err,
      ),
    );
    return (code: code, out: '$out', err: '$err');
  }

  test(
    'real quark reports merge, render, and pass an unchanged baseline',
    () async {
      final collect = await run(['collect']);
      expect(collect.code, exitPassed);
      expect(
        collect.out,
        'collected 8 attest files\ncollected 4 lighthouse files\n',
      );
      expect((await run(['report'])).code, exitPassed);
      expect((await run(['baseline', '--update'])).code, exitPassed);
      final ci = await run(['ci']);
      expect(ci.code, exitPassed);
      expect(ci.err, isEmpty);
      expect(ci.out, contains('overall 81 | a11y 94 | perf 69'));
      expect(ci.out, contains('0 new, 0 fixed, 71 unchanged'));
      expect(ci.out, endsWith('gate passed\n'));
      final report = jsonDecode(
        await File(p.join(reportDir, 'report.json')).readAsString(),
      ) as Map<String, Object?>;
      expect(report['metadata'], {
        'app': 'quark',
        'commit': quarkCommit,
        'timestamp': '2026-10-08T00:00:00.000Z',
        'flighthouseVersion': '0.1.0',
        'toolVersions': {'attest': '1.5.0', 'lighthouse': '13.5.0'},
      });
      final html = await File(p.join(reportDir, 'report.html')).readAsString();
      expect(html, startsWith('<!doctype html>'));
      expect(html, contains(escapeHtml('/recover/narrow')));
      expect(html, contains(escapeHtml('attest/contrast')));
    },
  );

  test(
    'adding a recorded quark screen fails on its real new findings',
    () async {
      expect((await run(['collect'])).code, exitPassed);
      await File(p.join(reportDir, 'raw', 'attest', 'recover-narrow.json'))
          .delete();
      expect((await run(['baseline', '--update'])).code, exitPassed);
      final previousBaseline = await File(baselinePath).readAsString();
      expect((await run(['collect'])).code, exitPassed);
      final ci = await run(['ci']);
      expect(ci.code, exitGateFailed);
      expect(ci.err, contains('new serious a11y finding on /recover/narrow'));
      expect(ci.out, endsWith('gate failed\n'));
      expect(await File(baselinePath).readAsString(), previousBaseline);
      expect(
        await File(p.join(reportDir, 'report.html')).readAsString(),
        contains('class="badge new"'),
      );
    },
  );

  test(
    'unusable input cannot pass the gate or replace a quark baseline',
    () async {
      expect((await run(['collect'])).code, exitPassed);
      expect((await run(['baseline', '--update'])).code, exitPassed);
      final previousBaseline = await File(baselinePath).readAsString();
      await File(p.join(reportDir, 'raw', 'attest', 'corrupt.json'))
          .writeAsBytes([0xff]);
      final ci = await run(['ci']);
      expect(ci.code, exitInputError);
      expect(ci.err, contains('the gate was not evaluated'));
      expect(ci.err, contains('corrupt.json'));
      expect(ci.out, isNot(contains('gate passed')));
      final baseline = await run(['baseline', '--update']);
      expect(baseline.code, exitInputError);
      expect(baseline.err, contains('the baseline was not touched'));
      expect(await File(baselinePath).readAsString(), previousBaseline);
    },
  );
}
