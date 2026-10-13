/// Flutter test helpers for flighthouse.
///
/// [writeTimelineSummary] writes an integration test's `TimelineSummary`
/// where `flighthouse collect` reads it. Call it from the driver script, for
/// example in the `responseDataCallback` of `integrationDriver`.
library;

export 'src/timeline_summary_writer.dart';
