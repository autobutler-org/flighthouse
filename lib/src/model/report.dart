import 'enums.dart';
import 'observations.dart';

/// The schema version this package reads and writes.
const int currentSchemaVersion = 1;

/// Where and how a report was produced.
final class ReportMetadata {
  /// Metadata for a run of [app] at [commit], taken at [timestamp].
  ReportMetadata({
    required this.app,
    required this.commit,
    required this.timestamp,
    required this.flighthouseVersion,
    required Map<Source, String> toolVersions,
  }) : toolVersions = Map.unmodifiable({
         for (final source in Source.values) source: ?toolVersions[source],
       });

  /// The app's name, from config.
  final String app;

  /// The git commit the report was produced from, when known.
  final String? commit;

  /// When the report was produced, in UTC.
  final DateTime timestamp;

  /// The flighthouse version that produced the report.
  final String flighthouseVersion;

  /// The version of each tool whose output was ingested.
  final Map<Source, String> toolVersions;
}

/// A score from 0 to 1 per category, and overall.
///
/// A category with no inputs is `null`, meaning not measured, never 1.
final class Scores {
  /// Scores for each category; a category missing from [categories] is null.
  Scores({required Map<Category, double?> categories, required this.overall})
    : categories = Map.unmodifiable({
        for (final category in Category.values) category: categories[category],
      });

  /// The score for every category, in [Category] order.
  final Map<Category, double?> categories;

  /// The weighted overall score, or null when nothing was measured.
  final double? overall;
}

/// One unified report: findings, the inputs to scoring, and the scores.
final class Report {
  /// A report holding unmodifiable copies of the given lists.
  Report({
    required this.metadata,
    required this.scores,
    required List<Finding> findings,
    required List<RuleOutcome> ruleOutcomes,
    required List<Measurement> measurements,
  }) : findings = List.unmodifiable(findings),
       ruleOutcomes = List.unmodifiable(ruleOutcomes),
       measurements = List.unmodifiable(measurements);

  /// Where and how the report was produced.
  final ReportMetadata metadata;

  /// The category and overall scores.
  final Scores scores;

  /// Every failure found.
  final List<Finding> findings;

  /// Every rule checked, passing or not.
  final List<RuleOutcome> ruleOutcomes;

  /// Every metric measured.
  final List<Measurement> measurements;
}
