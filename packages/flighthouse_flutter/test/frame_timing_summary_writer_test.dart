import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flighthouse_flutter/flighthouse_flutter.dart';
import 'package:flutter_driver/flutter_driver.dart';
import 'package:flutter_test/flutter_test.dart';

FrameTiming _frame(int start, int buildMicros, int rasterMicros) {
  final buildFinish = start + buildMicros;
  return FrameTiming(
    vsyncStart: start,
    buildStart: start,
    buildFinish: buildFinish,
    rasterStart: buildFinish,
    rasterFinish: buildFinish + rasterMicros,
    rasterFinishWallTime: buildFinish + rasterMicros,
  );
}

Map<String, dynamic> _summary() => json.decode(
  json.encode(
    FrameTimingSummarizer([_frame(0, 4000, 2000), _frame(20000, 18000, 3000)])
        .summary,
  ),
) as Map<String, dynamic>;

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('flighthouse_flutter_');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('writes each summary named for its report key', () async {
    final janky = _summary();

    final result = await writeFrameTimingSummaries({
      'perf-janky': janky,
      'perf-control': _summary(),
    }, directory: temp.path);

    expect(result.skipped, isEmpty);
    expect(result.writes.map((write) => write.path), [
      '${temp.path}/perf-janky.frame_timing_summary.json',
      '${temp.path}/perf-control.frame_timing_summary.json',
    ]);
    expect(result.writes, everyElement(isA<TimelineSummaryWritten>()));
    final decoded = json.decode(
      await File('${temp.path}/perf-janky.frame_timing_summary.json')
          .readAsString(),
    );
    expect(decoded, janky);
    expect(decoded, containsPair('frame_count', 2));
    expect(decoded, containsPair('worst_frame_build_time_millis', 18.0));
    expect(decoded, containsPair('frame_build_times', [4000, 18000]));
  });

  test('skips entries that are not frame timing summaries', () async {
    final missingKey = _summary()..remove('frame_rasterizer_times');
    final wrongType = _summary()..['frame_count'] = '2';
    final wrongTimes = _summary()..['frame_build_times'] = [4000.5];

    final result = await writeFrameTimingSummaries({
      'performance': _summary(),
      'missing': missingKey,
      'wrong-type': wrongType,
      'wrong-times': wrongTimes,
      'timeline': {'traceEvents': <Object>[]},
      'not a name': 3,
    }, directory: temp.path);

    expect(result.skipped, [
      'missing',
      'wrong-type',
      'wrong-times',
      'timeline',
      'not a name',
    ]);
    expect(
      result.writes.single.path,
      endsWith('/performance.frame_timing_summary.json'),
    );
    expect(temp.listSync().map((entity) => entity.uri.pathSegments.last), [
      'performance.frame_timing_summary.json',
    ]);
  });

  test('writes nothing for no response data', () async {
    final result = await writeFrameTimingSummaries(null, directory: temp.path);

    expect(result.writes, isEmpty);
    expect(result.skipped, isEmpty);
  });

  test('defaults to flighthouse/timeline under the test outputs', () async {
    final result = await writeFrameTimingSummaries({
      'flighthouse-default-directory': _summary(),
    });
    addTearDown(() => File(result.writes.single.path).delete());

    expect(
      result.writes.single.path,
      '$testOutputsDirectory/flighthouse/timeline/'
      'flighthouse-default-directory.frame_timing_summary.json',
    );
    expect(result.writes.single, isA<TimelineSummaryWritten>());
  });

  test('returns a failure when the directory cannot be created', () async {
    final blocker = File('${temp.path}/blocker');
    await blocker.writeAsString('');

    final result = await writeFrameTimingSummaries({
      'home': _summary(),
    }, directory: '${blocker.path}/timeline');

    switch (result.writes.single) {
      case TimelineSummaryWriteFailed(:final path, :final reason):
        expect(path, '${blocker.path}/timeline/home.frame_timing_summary.json');
        expect(reason, isNotEmpty);
      case TimelineSummaryWritten(:final path):
        fail('expected a failure, wrote $path');
    }
  });

  for (final name in ['', '.hidden', '..', 'a/b', r'a\b', 'files list', '/']) {
    test('rejects the report key "$name"', () {
      expect(
        () => writeFrameTimingSummaries({name: _summary()}),
        throwsArgumentError,
      );
    });
  }
}
