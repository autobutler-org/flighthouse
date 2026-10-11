import '../model/enums.dart';
import '../pipeline/route.dart';

/// Where a source's raw output files live.
typedef SourceConfig = ({String dir});

/// The log-normal control points for scoring one metric.
///
/// A value at [p10] scores 0.9 and a value at [median] scores 0.5.
typedef ControlPoints = ({double p10, double median});

/// How the Flutter web application is built.
final class WebBuildConfig {
  /// A build command and its output directory, relative to the project.
  WebBuildConfig({required List<String> command, required this.outputDir})
    : command = List.unmodifiable(command);

  /// The executable followed by its arguments.
  final List<String> command;

  /// The build output directory, relative to the web project.
  final String outputDir;
}

/// How the built web application is served.
final class WebServeConfig {
  /// A server bound to [port], where zero requests an OS-assigned port.
  const WebServeConfig({required this.port});

  /// The loopback port to bind.
  final int port;
}

/// When a Flutter web route is ready for collection.
final class WebReadinessConfig {
  /// Readiness bounded by [timeout] and optionally marked by [selector].
  const WebReadinessConfig({required this.timeout, required this.selector});

  /// The maximum wait for navigation, semantics, and each auth step.
  final Duration timeout;

  /// An optional application-specific CSS selector.
  final String? selector;
}

/// The browser viewport shared by web audit tools.
final class WebViewportConfig {
  /// A viewport with its CSS dimensions and device scale.
  const WebViewportConfig({
    required this.width,
    required this.height,
    required this.deviceScaleFactor,
  });

  /// The viewport width in CSS pixels.
  final int width;

  /// The viewport height in CSS pixels.
  final int height;

  /// The ratio of device pixels to CSS pixels.
  final double deviceScaleFactor;
}

/// One configured browser authentication action.
sealed class WebAuthStep {
  /// An action targeting [selector].
  const WebAuthStep({required this.selector});

  /// The CSS selector targeted by this action.
  final String selector;
}

/// An authentication action that types an environment-sourced value.
final class WebTypeAuthStep extends WebAuthStep {
  /// A typing action that reads [valueFromEnv] only when it runs.
  const WebTypeAuthStep({required super.selector, required this.valueFromEnv});

  /// The name of the environment variable holding the value.
  final String valueFromEnv;
}

/// An authentication action that clicks an element.
final class WebClickAuthStep extends WebAuthStep {
  /// A click action targeting [selector].
  const WebClickAuthStep({required super.selector});
}

/// An authentication action that waits for an element.
final class WebWaitAuthStep extends WebAuthStep {
  /// A wait action targeting [selector].
  const WebWaitAuthStep({required super.selector});
}

/// Browser authentication performed once before route collection.
final class WebAuthConfig {
  /// Authentication at [url] through the ordered [steps].
  WebAuthConfig({required this.url, required List<WebAuthStep> steps})
    : steps = List.unmodifiable(steps);

  /// The application path containing the authentication flow.
  final String url;

  /// The ordered actions used to authenticate.
  final List<WebAuthStep> steps;
}

/// The simulated network and CPU throttling passed to Lighthouse.
typedef LighthouseThrottling = ({
  double rttMs,
  double throughputKbps,
  double cpuSlowdownMultiplier,
});

/// The throttling Lighthouse's desktop preset uses.
const LighthouseThrottling defaultLighthouseThrottling = (
  rttMs: 40,
  throughputKbps: 10240,
  cpuSlowdownMultiplier: 1,
);

/// How Lighthouse is invoked for web collection.
final class WebLighthouseConfig {
  /// A Lighthouse executable followed by its fixed arguments, and the
  /// [throttling] it simulates.
  WebLighthouseConfig({
    required List<String> command,
    this.throttling = defaultLighthouseThrottling,
  }) : command = List.unmodifiable(command);

  /// The executable followed by its fixed arguments.
  final List<String> command;

  /// The simulated network and CPU throttling.
  final LighthouseThrottling throttling;
}

/// Which axe-core script web collection uses.
final class WebAxeConfig {
  /// A pinned [version] or an existing [scriptPath].
  const WebAxeConfig({required this.version, required this.scriptPath});

  /// The axe-core version to acquire when [scriptPath] is absent.
  final String version;

  /// An optional script path relative to the configuration file.
  final String? scriptPath;
}

/// Configuration for building and auditing a Flutter web application.
final class WebConfig {
  /// A web run; collections are copied and made unmodifiable.
  WebConfig({
    required this.projectDir,
    required this.build,
    required this.serve,
    required List<String> routes,
    required this.readiness,
    required this.viewport,
    required this.auth,
    required this.lighthouse,
    required this.axe,
  }) : routes = List.unmodifiable(routes);

  /// The Flutter project directory, relative to the configuration file.
  final String projectDir;

  /// Build command and output location.
  final WebBuildConfig build;

  /// Static server settings.
  final WebServeConfig serve;

  /// Application paths collected in order.
  final List<String> routes;

  /// Navigation and application readiness settings.
  final WebReadinessConfig readiness;

  /// The viewport shared by browser audits.
  final WebViewportConfig viewport;

  /// Optional authentication performed before route collection.
  final WebAuthConfig? auth;

  /// Lighthouse process settings.
  final WebLighthouseConfig lighthouse;

  /// axe-core acquisition settings.
  final WebAxeConfig axe;
}

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

/// The Lighthouse audit scores that decide what is a finding.
///
/// An audit scoring below [passingScore] is a finding, and a measured audit
/// scoring below [seriousScore] is serious rather than moderate.
typedef LighthouseScoreLines = ({double passingScore, double seriousScore});

/// Lighthouse's own passing and failing score bands.
const LighthouseScoreLines defaultLighthouseScoreLines = (
  passingScore: 0.9,
  seriousScore: 0.5,
);

/// How a new finding that carries a metric is gated.
enum MetricFindingsGate {
  /// Only its category score drop can fail the gate.
  score('score'),

  /// It fails the gate like any other new finding.
  newFinding('new');

  const MetricFindingsGate(this.id);

  /// The identifier used in config.
  final String id;
}

/// How category and metric scores are computed.
final class ScoringConfig {
  /// Scoring with the given [weights], per-metric [metrics] control points,
  /// and [lighthouse] score lines.
  ScoringConfig({
    required Map<Category, double> weights,
    required Map<String, ControlPoints> metrics,
    this.lighthouse = defaultLighthouseScoreLines,
  }) : weights = Map.unmodifiable({
         for (final category in Category.values)
           category: weights[category] ?? 0,
       }),
       metrics = Map.unmodifiable(metrics);

  /// The weight of each category in the overall score; they sum to 1.
  final Map<Category, double> weights;

  /// Control points for each metric that is scored, by metric name.
  final Map<String, ControlPoints> metrics;

  /// The score lines the Lighthouse adapter applies to audits.
  final LighthouseScoreLines lighthouse;
}

/// When `flighthouse ci` fails.
final class GateConfig {
  /// A gate with the given thresholds.
  GateConfig({
    required this.minSeverity,
    required this.overallMaxDrop,
    required Map<Category, double> categoryMaxDrop,
    this.metricFindings = MetricFindingsGate.score,
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

  /// Whether a new finding that carries a metric fails by itself.
  final MetricFindingsGate metricFindings;
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
    required this.web,
  }) : sources = Map.unmodifiable(sources),
       routePatterns = List.unmodifiable(routePatterns),
       auditSources = Set.unmodifiable({
         ...sources.keys,
         if (web != null) Source.lighthouse,
         if (web != null) Source.axe,
       });

  /// The app's name, shown in reports.
  final String app;

  /// The directory raw outputs and reports are written to.
  final String reportDir;

  /// The committed baseline file.
  final String baselinePath;

  /// The configured sources and where their raw outputs live.
  final Map<Source, SourceConfig> sources;

  /// Sources read by report commands, including web-generated outputs.
  final Set<Source> auditSources;

  /// Route patterns for normalization, first match wins.
  final List<RoutePattern> routePatterns;

  /// Scoring weights and metric control points.
  final ScoringConfig scoring;

  /// The CI gate thresholds.
  final GateConfig gate;

  /// Optional Flutter web collection settings.
  final WebConfig? web;
}
