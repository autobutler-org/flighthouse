/// Flutter test helpers for flighthouse.
///
/// [writeTimelineSummary] writes an integration test's `TimelineSummary`
/// where `flighthouse collect` reads it. Call it from the driver script, for
/// example in the `responseDataCallback` of `integrationDriver`.
///
/// [writeFrameTimingSummaries] writes the `watchPerformance` reports in an
/// integration test's response data, the frame timing source on web.
library;

export 'src/frame_timing_summary_writer.dart';
export 'src/timeline_summary_writer.dart';
