import 'dart:convert';
import 'dart:io';

import 'package:flighthouse_flutter/flighthouse_flutter.dart';
import 'package:flutter_driver/flutter_driver.dart';
import 'package:flutter_test/flutter_test.dart';

TimelineSummary _summarize(List<Map<String, Object>> events) =>
    TimelineSummary.summarize(
      Timeline.fromJson(<String, dynamic>{'traceEvents': events}),
    );

Map<String, Object> _event(String name, String phase, int micros) => {
  'name': name,
  'ph': phase,
  'ts': micros,
};

final TimelineSummary _twoFrames = _summarize([
  _event('Frame', 'B', 1000),
  _event('Frame', 'E', 5000),
  _event('GPURasterizer::Draw', 'B', 5500),
  _event('GPURasterizer::Draw', 'E', 7500),
  _event('Frame', 'B', 20000),
  _event('Frame', 'E', 38000),
  _event('GPURasterizer::Draw', 'B', 38500),
  _event('GPURasterizer::Draw', 'E', 41500),
]);

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('flighthouse_flutter_');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('writes the summary JSON named for the scenario', () async {
    final directory = '${temp.path}/out/timeline';

    final written = await writeTimelineSummary(
      _twoFrames,
      name: 'files-scroll',
      directory: directory,
    );

    final path = '$directory/files-scroll.timeline_summary.json';
    expect(written, isA<TimelineSummaryWritten>());
    expect(written.path, path);
    final decoded = json.decode(await File(path).readAsString());
    expect(decoded, json.decode(json.encode(_twoFrames.summaryJson)));
    expect(decoded, containsPair('frame_count', 2));
    expect(decoded, containsPair('worst_frame_build_time_millis', 18.0));
    expect(decoded, containsPair('missed_frame_build_budget_count', 1));
    expect(decoded, containsPair('frame_build_times', [4000, 18000]));
  });

  test('replaces an earlier summary with the same name', () async {
    final oneFrame = _summarize([
      _event('Frame', 'B', 0),
      _event('Frame', 'E', 1000),
      _event('GPURasterizer::Draw', 'B', 1000),
      _event('GPURasterizer::Draw', 'E', 2000),
    ]);
    await writeTimelineSummary(oneFrame, name: 'home', directory: temp.path);

    await writeTimelineSummary(_twoFrames, name: 'home', directory: temp.path);

    final decoded = json.decode(
      await File('${temp.path}/home.timeline_summary.json').readAsString(),
    );
    expect(decoded, containsPair('frame_count', 2));
  });

  test('defaults to flighthouse/timeline under the test outputs', () async {
    final written = await writeTimelineSummary(
      _summarize(const []),
      name: 'home',
    );

    expect(
      written.path,
      '$testOutputsDirectory/flighthouse/timeline/home.timeline_summary.json',
    );
  });

  test('returns a failure for a timeline with no frames', () async {
    final written = await writeTimelineSummary(
      _summarize(const []),
      name: 'home',
      directory: temp.path,
    );

    switch (written) {
      case TimelineSummaryWriteFailed(:final path, :final reason):
        expect(path, '${temp.path}/home.timeline_summary.json');
        expect(reason, startsWith('The TimelineSummary had no events'));
      case TimelineSummaryWritten():
        fail('expected a failure, wrote ${written.path}');
    }
    expect(File(written.path).existsSync(), isFalse);
  });

  test('returns a failure when the directory cannot be created', () async {
    final blocker = File('${temp.path}/blocker');
    await blocker.writeAsString('');

    final written = await writeTimelineSummary(
      _twoFrames,
      name: 'home',
      directory: '${blocker.path}/timeline',
    );

    switch (written) {
      case TimelineSummaryWriteFailed(:final path, :final reason):
        expect(path, '${blocker.path}/timeline/home.timeline_summary.json');
        expect(reason, isNotEmpty);
      case TimelineSummaryWritten():
        fail('expected a failure, wrote ${written.path}');
    }
  });

  for (final name in ['', '.hidden', '..', 'a/b', r'a\b', 'files list', '/']) {
    test('rejects the name "$name"', () {
      expect(
        () => writeTimelineSummary(_twoFrames, name: name),
        throwsArgumentError,
      );
    });
  }
}
