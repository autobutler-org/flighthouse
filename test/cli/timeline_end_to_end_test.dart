import 'dart:io';

import 'package:flighthouse/src/cli/cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const fixtures = 'test/fixtures/e2e_timeline';
const config = '$fixtures/flighthouse.yaml';
const expected = '$fixtures/expected';
const committedBaseline = '$fixtures/flighthouse-baseline.json';
const control =
    'test/fixtures/timeline/3.47.7/perf-control.frame_timing_summary.json';
final updateGoldens = Platform.environment['FLIGHTHOUSE_UPDATE_GOLDENS'] == '1';

typedef Run = ({int code, String out, String err});

Future<Run> run(String configPath, List<String> arguments) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = await runCli(
    ['--config', configPath, ...arguments],
    version: '0.0.1',
    environment: (
      now: () => DateTime.utc(2026, 10, 18, 12),
      commitOf: (_) async => 'e2e0000',
      out: out,
      err: err,
    ),
  );
  return (code: code, out: '$out', err: '$err');
}

void expectGolden(String actual, String goldenPath) {
  final golden = File(goldenPath);
  if (updateGoldens) {
    golden.writeAsStringSync(actual);
  }
  expect(
    actual,
    golden.readAsStringSync(),
    reason: 'golden $goldenPath is stale',
  );
}

void main() {
  late Directory scratch;

  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('flighthouse-e2e-timeline');
  });

  tearDown(() => scratch.delete(recursive: true));

  test('the committed baseline is the control recording alone', () async {
    final timeline = Directory(p.join(scratch.path, 'timeline'))..createSync();
    File(control).copySync(p.join(timeline.path, p.basename(control)));
    File(p.join(scratch.path, 'flighthouse.yaml')).writeAsStringSync('''
app: web_fixture
reportDir: report
baseline: flighthouse-baseline.json
sources:
  timeline:
    dir: timeline
''');
    final configPath = p.join(scratch.path, 'flighthouse.yaml');

    expect((await run(configPath, ['collect'])).code, exitPassed);
    final update = await run(configPath, ['baseline', '--update']);
    expect(update.err, isEmpty);
    expect(update.code, exitPassed);
    expectGolden(
      File(p.join(scratch.path, 'flighthouse-baseline.json'))
          .readAsStringSync(),
      committedBaseline,
    );
  });

  test(
    'the janky recording fails ci with metricFindings new against the control '
    'baseline',
    () async {
      final reportDir = ['--report-dir', scratch.path];
      final collect = await run(config, [...reportDir, 'collect']);
      expect(collect.err, isEmpty);
      expect(collect.code, exitPassed);
      expect(collect.out, 'collected 2 timeline files\n');

      final ci = await run(config, [...reportDir, 'ci']);
      expect(ci.code, exitGateFailed);
      expect(
        ci.out.replaceAll(scratch.path, '<reportDir>'),
        'web_fixture: overall n/a | a11y n/a | perf n/a | responsiveness n/a | '
        'memory n/a | best-practices n/a\n'
        '2 new, 0 fixed, 2 unchanged\n'
        'gate failed\n'
        'details in <reportDir>/report.html; fix the failures above, or accept '
        'them as the new baseline with flighthouse baseline --update\n',
      );
      expect(
        ci.err,
        'FAIL new critical responsiveness finding on perf-janky: '
        'frame-build-budget: 17 of 17 frames missed the 16 ms build budget; '
        'the average build time was 124.5 ms\n'
        'FAIL new minor responsiveness finding on perf-janky: '
        'frame-rasterizer-budget: 1 of 17 frames missed the 16 ms raster '
        'budget; the average raster time was 11.0 ms\n',
      );
      expectGolden(
        File(p.join(scratch.path, 'report.json')).readAsStringSync(),
        '$expected/report.json',
      );
    },
  );
}
