import 'dart:convert';

import '../../model/enums.dart';
import '../../model/json_decode.dart';
import '../../model/observations.dart';
import '../../pipeline/fingerprint.dart';
import '../../result/failure.dart';
import '../../result/result.dart';
import '../adapter.dart';

/// The file name suffix of a `FrameTimingSummarizer` summary.
const String frameTimingSummarySuffix = '.frame_timing_summary.json';

/// The file name suffix of a `TimelineSummary` summary.
const String timelineSummarySuffix = '.timeline_summary.json';

/// The per-frame budget `FrameTimingSummarizer` counts missed frames against.
const double frameBudgetMillis = 16;

const String _unversioned = 'unknown';

typedef _Phase = ({String key, String rule, String noun});

const List<_Phase> _phases = [
  (key: 'build', rule: 'frame-build-budget', noun: 'build'),
  (key: 'rasterizer', rule: 'frame-rasterizer-budget', noun: 'raster'),
];

const List<String> _statistics = [
  'average',
  '90th_percentile',
  '99th_percentile',
  'worst',
];

String _averageKey(_Phase phase) => 'average_frame_${phase.key}_time_millis';

String _missedKey(_Phase phase) => 'missed_frame_${phase.key}_budget_count';

final List<String> _timeKeys = List.unmodifiable([
  for (final phase in _phases)
    for (final statistic in _statistics)
      '${statistic}_frame_${phase.key}_time_millis',
]);

final List<String> _missedKeys = List.unmodifiable(_phases.map(_missedKey));

const String _frameCountKey = 'frame_count';

Decoded<int> _decodeCount(Object? json, String path) => switch (json) {
  final int count when count >= 0 => Ok(count),
  _ => mismatch(path, 'an integer of at least 0', json),
};

Decoded<double> _decodeCountValue(Object? json, String path) =>
    _decodeCount(json, path).map((count) => count.toDouble());

final Map<String, Decoder<Object>> _unmeasured = Map.unmodifiable({
  for (final statistic in _statistics)
    for (final cache in [
      'layer_cache_count',
      'layer_cache_memory',
      'picture_cache_count',
      'picture_cache_memory',
    ])
      '${statistic}_$cache': decodeNonNegative,
  'frame_build_times': listDecoder(_decodeCount),
  'frame_rasterizer_times': listDecoder(_decodeCount),
  'new_gen_gc_count': decodeInt,
  'old_gen_gc_count': decodeInt,
});

final List<String> _summaryKeys = List.unmodifiable([
  ..._timeKeys,
  ..._missedKeys,
  _frameCountKey,
  ..._unmeasured.keys,
]);

typedef _Summary = ({Map<String, double> measured, int frameCount});

Decoded<Map<String, double>> _readValues(
  JsonObject object,
  List<String> keys,
  Decoder<double> decode,
) => traverse(
  keys,
  (key) => readField(
    object,
    key,
    rootPath,
    decode,
  ).map((value) => MapEntry(key, value)),
).map(Map.fromEntries);

Decoded<_Summary> _decodeSummary(Object? json) =>
    readObject(json, rootPath, _summaryKeys).flatMap(
      (object) => switch ((
        _readValues(object, _timeKeys, decodeNonNegative),
        _readValues(object, _missedKeys, _decodeCountValue),
        readField(object, _frameCountKey, rootPath, _decodeCount),
        traverse(
          _unmeasured.entries,
          (entry) => readField(object, entry.key, rootPath, entry.value),
        ),
      )) {
        (
          Ok(value: final times),
          Ok(value: final missed),
          Ok(value: final frameCount),
          Ok(),
        ) =>
          Ok((
            measured: Map.unmodifiable({...times, ...missed}),
            frameCount: frameCount,
          )),
        (final times, final missed, final frameCount, final unmeasured) => Err(
          firstError([times, missed, frameCount, unmeasured]),
        ),
      },
    );

Severity? severityOf({required double averageMillis, required double missed}) =>
    switch (averageMillis / frameBudgetMillis) {
      > 4 => Severity.critical,
      > 2 => Severity.serious,
      > 1 => Severity.moderate,
      _ when missed > 0 => Severity.minor,
      _ => null,
    };

Metric _metricOf(String key, double value) => (
  name: key,
  value: value,
  unit: _missedKeys.contains(key) ? MetricUnit.count : MetricUnit.ms,
);

List<Finding> _findingsOf(_Summary summary, String route) => [
  for (final phase in _phases)
    if (severityOf(
          averageMillis: summary.measured[_averageKey(phase)]!,
          missed: summary.measured[_missedKey(phase)]!,
        )
        case final severity?)
      (
        fingerprint: fingerprint(
          source: Source.timeline,
          rule: phase.rule,
          route: route,
          target: null,
        ),
        source: Source.timeline,
        category: Category.responsiveness,
        severity: severity,
        rule: phase.rule,
        route: route,
        target: null,
        message:
            '${summary.measured[_missedKey(phase)]!.toInt()} of '
            '${summary.frameCount} frames missed the '
            '${frameBudgetMillis.toInt()} ms ${phase.noun} budget; the average '
            '${phase.noun} time was '
            '${summary.measured[_averageKey(phase)]!.toStringAsFixed(1)} ms',
        metric: _metricOf(
          _averageKey(phase),
          summary.measured[_averageKey(phase)]!,
        ),
      ),
];

AdapterOutput _outputOf(_Summary summary, String route) => AdapterOutput(
  toolVersion: _unversioned,
  findings: _findingsOf(summary, route),
  ruleOutcomes: const [],
  measurements: [
    for (final MapEntry(:key, :value) in summary.measured.entries)
      (
        source: Source.timeline,
        category: Category.responsiveness,
        route: route,
        metric: _metricOf(key, value),
        weight: 1,
        toolScore: null,
      ),
  ],
);

String _fileNameOf(String path) => path.split(RegExp(r'[/\\]')).last;

/// Turns one integration_test frame timing summary into responsiveness
/// findings and measurements.
///
/// The format comes from the file name. A
/// `<scenario>.frame_timing_summary.json` is the summary `watchPerformance`
/// reports, and the scenario is the route. Its frame build and raster times
/// and missed-budget counts become measurements, scored when the metric has control points; its GC
/// counts and cache values are validated but not measured, since the web
/// engine does not report them. Each phase whose average time exceeds the
/// 16 ms budget, or that missed it at all, is one finding: minor for
/// occasional misses, then moderate, serious, and critical above one, two,
/// and four budgets. The summary names no Flutter version, so any key outside
/// the Flutter 3.47.7 summary is a failure rather than a best-effort parse.
/// `TimelineSummary` files and any other file name are failures.
Result<AdapterOutput, Failure> parseFrameTiming(RawArtifact artifact) {
  AdapterFailure failure(String problem) => AdapterFailure(
    tool: Source.timeline.id,
    artifactPath: artifact.path,
    problem: problem,
  );
  final name = _fileNameOf(artifact.path);
  if (name.endsWith(timelineSummarySuffix)) {
    return Err(
      failure(
        'TimelineSummary output is not read yet; write frame timing with '
        'watchPerformance and writeFrameTimingSummaries instead',
      ),
    );
  }
  if (!name.endsWith(frameTimingSummarySuffix) ||
      name.length == frameTimingSummarySuffix.length) {
    return Err(
      failure(
        '$name is not named <scenario>$frameTimingSummarySuffix or '
        '<scenario>$timelineSummarySuffix',
      ),
    );
  }
  final route = name.substring(
    0,
    name.length - frameTimingSummarySuffix.length,
  );
  final Object? json;
  try {
    json = jsonDecode(artifact.contents);
  } on FormatException catch (error) {
    return Err(failure('not valid JSON: ${error.message}'));
  }
  return _decodeSummary(json)
      .mapErr<Failure>((error) => failure(describe(error)))
      .map((summary) => _outputOf(summary, route));
}
