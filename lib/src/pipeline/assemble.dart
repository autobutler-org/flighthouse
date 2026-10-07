import '../adapters/adapter.dart';
import '../adapters/attest/attest_adapter.dart';
import '../adapters/lighthouse/lighthouse_adapter.dart';
import '../config/config.dart';
import '../model/enums.dart';
import '../model/report.dart';
import '../result/failure.dart';
import '../result/result.dart';
import 'normalize.dart';
import 'scoring.dart';

/// Turns one raw artifact into findings, rule outcomes, and measurements.
typedef Adapter = Result<AdapterOutput, Failure> Function(RawArtifact artifact);

/// The adapter for each source that has one.
const Map<Source, Adapter> defaultAdapters = {
  Source.attest: parseAttest,
  Source.lighthouse: parseLighthouse,
};

/// A report built from every usable artifact, and every failure on the way.
typedef Assembled = ({Report report, List<Failure> failures});

String _versionsOf(Iterable<String> versions) =>
    (versions.toSet().toList()..sort()).join(', ');

/// Parses, normalizes, dedupes, and scores [artifacts] into a [Report].
///
/// Every artifact is parsed even when others fail, so all problems are
/// reported at once; failed artifacts are left out of the report. A source
/// with no adapter fails once, naming the source.
Assembled assembleReport({
  required Config config,
  required List<RawArtifact> artifacts,
  required DateTime timestamp,
  required String? commit,
  required String flighthouseVersion,
  Map<Source, Adapter> adapters = defaultAdapters,
}) {
  final unsupported = {
    for (final artifact in artifacts)
      if (!adapters.containsKey(artifact.source)) artifact.source,
  };
  final (outputs, adapterFailures) = partition([
    for (final artifact in artifacts)
      if (adapters[artifact.source] case final adapter?)
        adapter(artifact)
            .map((output) => (source: artifact.source, output: output)),
  ]);
  final observations = dedupe(
    normalize((
      findings: [for (final item in outputs) ...item.output.findings],
      ruleOutcomes: [for (final item in outputs) ...item.output.ruleOutcomes],
      measurements: [for (final item in outputs) ...item.output.measurements],
    ), config.routePatterns),
  );
  return (
    report: Report(
      metadata: ReportMetadata(
        app: config.app,
        commit: commit,
        timestamp: timestamp.toUtc(),
        flighthouseVersion: flighthouseVersion,
        toolVersions: {
          for (final source in Source.values)
            if (outputs.where((item) => item.source == source).toList()
                case final ofSource when ofSource.isNotEmpty)
              source: _versionsOf(
                ofSource.map((item) => item.output.toolVersion),
              ),
        },
      ),
      scores: score(
        ruleOutcomes: observations.ruleOutcomes,
        measurements: observations.measurements,
        scoring: config.scoring,
      ),
      findings: observations.findings,
      ruleOutcomes: observations.ruleOutcomes,
      measurements: observations.measurements,
    ),
    failures: List.unmodifiable([
      for (final source in unsupported)
        AdapterFailure(
          tool: source.id,
          artifactPath: config.sources[source]?.dir ?? source.id,
          problem: 'flighthouse cannot read ${source.id} output yet',
        ),
      ...adapterFailures,
    ]),
  );
}
