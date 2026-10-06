import 'dart:io';

import 'package:flighthouse/src/cli/cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const config = 'test/fixtures/e2e/flighthouse.yaml';
const expected = 'test/fixtures/e2e/expected';
final updateGoldens = Platform.environment['FLIGHTHOUSE_UPDATE_GOLDENS'] == '1';

void main() {
  late Directory reportDir;

  setUp(() async {
    reportDir = await Directory.systemTemp.createTemp('flighthouse-e2e');
  });

  tearDown(() => reportDir.delete(recursive: true));

  Future<({int code, String out, String err})> run(String command) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runCli(
      ['--config', config, '--report-dir', reportDir.path, command],
      version: '0.0.1',
      environment: (
        now: () => DateTime.utc(2026, 10, 6, 12),
        commitOf: (_) async => 'e2e0000',
        out: out,
        err: err,
      ),
    );
    return (code: code, out: '$out', err: '$err');
  }

  void expectGolden(String name) {
    final actual = File(p.join(reportDir.path, name)).readAsStringSync();
    final golden = File(p.join(expected, name));
    if (updateGoldens) {
      golden.writeAsStringSync(actual);
    }
    expect(actual, golden.readAsStringSync(), reason: 'golden $name is stale');
  }

  test('collect then ci passes against the committed baseline', () async {
    expect((await run('collect')).code, exitPassed);
    final ci = await run('ci');
    expect(ci.err, isEmpty);
    expect(ci.code, exitPassed);
    expect(
      ci.out,
      'quark: overall 77 | a11y 71 | perf 80 | responsiveness n/a | '
      'memory n/a | best-practices 87\n'
      '0 new, 0 fixed, 29 unchanged\n'
      'gate passed\n',
    );
    expectGolden('report.json');
    expectGolden('report.html');
  });
}
