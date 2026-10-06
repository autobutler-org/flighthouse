import '../model/enums.dart';
import '../pipeline/route.dart';

/// Where a source's raw output files live.
typedef SourceConfig = ({String dir});

/// The log-normal control points for scoring one metric.
///
/// A value at [p10] scores 0.9 and a value at [median] scores 0.5.
typedef ControlPoints = ({double p10, double median});

/// The default weight of each category in the overall score.
const Map<Category, double> defaultCategoryWeights = {
  Category.a11y: 0.3,
  Category.perf: 0.3,
  Category.responsiveness: 0.2,
  Category.memory: 0.1,
  Category.bestPractices: 0.1,
};

/// The default largest overall score drop, in points, before the gate fails.
const double defaultOverallMaxDrop = 2;

/// The default largest score drop per category, in points.
const Map<Category, double> defaultCategoryMaxDrop = {
  Category.a11y: 2,
  Category.perf: 5,
  Category.responsiveness: 2,
  Category.memory: 2,
  Category.bestPractices: 2,
};

/// How category and metric scores are computed.
final class ScoringConfig {
  /// Scoring with the given [weights] and per-metric [metrics] control points.
  ScoringConfig({
    required Map<Category, double> weights,
    required Map<String, ControlPoints> metrics,
  }) : weights = Map.unmodifiable({
         for (final category in Category.values)
           category: weights[category] ?? 0,
       }),
       metrics = Map.unmodifiable(metrics);

  /// The weight of each category in the overall score; they sum to 1.
  final Map<Category, double> weights;

  /// Control points for each metric that is scored, by metric name.
  final Map<String, ControlPoints> metrics;
}

/// When `flighthouse ci` fails.
final class GateConfig {
  /// A gate with the given thresholds.
  GateConfig({
    required this.minSeverity,
    required this.overallMaxDrop,
    required Map<Category, double> categoryMaxDrop,
  }) : categoryMaxDrop = Map.unmodifiable({
         for (final category in Category.values)
           category:
               categoryMaxDrop[category] ?? defaultCategoryMaxDrop[category]!,
       });

  /// New findings at or above this severity fail the gate.
  final Severity minSeverity;

  /// The largest overall score drop, in points, that still passes.
  final double overallMaxDrop;

  /// The largest score drop per category, in points, that still passes.
  final Map<Category, double> categoryMaxDrop;
}

/// The parsed contents of `flighthouse.yaml`.
final class Config {
  /// A configuration; collections are copied and made unmodifiable.
  Config({
    required this.app,
    required this.reportDir,
    required this.baselinePath,
    required Map<Source, SourceConfig> sources,
    required List<RoutePattern> routePatterns,
    required this.scoring,
    required this.gate,
  }) : sources = Map.unmodifiable(sources),
       routePatterns = List.unmodifiable(routePatterns);

  /// The app's name, shown in reports.
  final String app;

  /// The directory raw outputs and reports are written to.
  final String reportDir;

  /// The committed baseline file.
  final String baselinePath;

  /// The configured sources and where their raw outputs live.
  final Map<Source, SourceConfig> sources;

  /// Route patterns for normalization, first match wins.
  final List<RoutePattern> routePatterns;

  /// Scoring weights and metric control points.
  final ScoringConfig scoring;

  /// The CI gate thresholds.
  final GateConfig gate;
}
