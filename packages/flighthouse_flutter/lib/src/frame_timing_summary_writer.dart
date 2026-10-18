import 'summary_file.dart';
import 'timeline_summary_writer.dart';

/// The outcome of [writeFrameTimingSummaries].
final class FrameTimingSummaryWrites {
  /// The [writes] made and the [skipped] response data keys.
  FrameTimingSummaryWrites({
    required List<TimelineSummaryWrite> writes,
    required List<String> skipped,
  }) : writes = List.unmodifiable(writes),
       skipped = List.unmodifiable(skipped);

  /// One write per response data entry that held a frame timing summary.
  final List<TimelineSummaryWrite> writes;

  /// The response data keys whose values were not frame timing summaries.
  final List<String> skipped;
}

const List<String> _timeListKeys = [
  'frame_build_times',
  'frame_rasterizer_times',
];

const List<String> _numberKeys = [
  'average_frame_build_time_millis',
  '90th_percentile_frame_build_time_millis',
  '99th_percentile_frame_build_time_millis',
  'worst_frame_build_time_millis',
  'missed_frame_build_budget_count',
  'average_frame_rasterizer_time_millis',
  '90th_percentile_frame_rasterizer_time_millis',
  '99th_percentile_frame_rasterizer_time_millis',
  'worst_frame_rasterizer_time_millis',
  'missed_frame_rasterizer_budget_count',
  'average_layer_cache_count',
  '90th_percentile_layer_cache_count',
  '99th_percentile_layer_cache_count',
  'worst_layer_cache_count',
  'average_layer_cache_memory',
  '90th_percentile_layer_cache_memory',
  '99th_percentile_layer_cache_memory',
  'worst_layer_cache_memory',
  'average_picture_cache_count',
  '90th_percentile_picture_cache_count',
  '99th_percentile_picture_cache_count',
  'worst_picture_cache_count',
  'average_picture_cache_memory',
  '90th_percentile_picture_cache_memory',
  '99th_percentile_picture_cache_memory',
  'worst_picture_cache_memory',
  'frame_count',
  'new_gen_gc_count',
  'old_gen_gc_count',
];

bool _isFrameTimingSummary(Map<String, dynamic> value) =>
    _numberKeys.every((key) => value[key] is num) &&
    _timeListKeys.every(
      (key) => switch (value[key]) {
        final List<dynamic> times => times.every((time) => time is int),
        _ => false,
      },
    );

/// Writes each `watchPerformance` report in [responseData] where
/// `flighthouse collect` reads frame timing summaries.
///
/// Pass the response data `integrationDriver` gives its
/// `responseDataCallback`. Each entry whose value has every key of a
/// `FrameTimingSummarizer` summary is written unchanged to
/// `<directory>/<key>.frame_timing_summary.json`, so the `reportKey` passed to
/// `watchPerformance` names the route or scenario. Such a key must start with a
/// letter or digit and contain only letters, digits, `.`, `_`, and `-`; any
/// other key throws an [ArgumentError]. Entries that are not summaries are
/// listed in [FrameTimingSummaryWrites.skipped].
///
/// [directory] defaults to the same `build/flighthouse/timeline` as
/// [writeTimelineSummary]. A file system error is returned as a
/// [TimelineSummaryWriteFailed], never thrown.
Future<FrameTimingSummaryWrites> writeFrameTimingSummaries(
  Map<String, dynamic>? responseData, {
  String? directory,
}) async {
  final writes = <TimelineSummaryWrite>[];
  final skipped = <String>[];
  for (final MapEntry(:key, :value) in (responseData ?? const {}).entries) {
    if (value is Map<String, dynamic> && _isFrameTimingSummary(value)) {
      writes.add(
        await writeSummaryJson(
          summaryPath(key, 'frame_timing_summary.json', directory),
          value,
        ),
      );
    } else {
      skipped.add(key);
    }
  }
  return FrameTimingSummaryWrites(writes: writes, skipped: skipped);
}
