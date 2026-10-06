import '../model/enums.dart';
import '../model/observations.dart';
import 'fingerprint.dart';
import 'route.dart';

/// Rewrites a tool's target into a form that is stable across builds.
typedef TargetNormalizer = String? Function(String? target);

/// Findings, rule outcomes, and measurements gathered from every source.
typedef Observations = ({
  List<Finding> findings,
  List<RuleOutcome> ruleOutcomes,
  List<Measurement> measurements,
});

String? keepTarget(String? target) => target;

/// The target normalizer for each source; sources not listed keep targets.
///
/// Every source keeps its targets as reported until real Flutter web output
/// shows which parts are volatile (ADR 0007).
const Map<Source, TargetNormalizer> defaultTargetNormalizers = {};

/// Normalizes routes and targets and recomputes fingerprints from them.
Observations normalize(
  Observations observations,
  List<RoutePattern> routePatterns, {
  Map<Source, TargetNormalizer> targetNormalizers = defaultTargetNormalizers,
}) {
  String routeOf(String route) => normalizeRoute(route, routePatterns);
  return (
    findings: [
      for (final finding in observations.findings)
        _normalizeFinding(
          finding,
          routeOf(finding.route),
          (targetNormalizers[finding.source] ?? keepTarget)(finding.target),
        ),
    ],
    ruleOutcomes: [
      for (final outcome in observations.ruleOutcomes)
        (
          source: outcome.source,
          category: outcome.category,
          rule: outcome.rule,
          route: routeOf(outcome.route),
          weight: outcome.weight,
          passed: outcome.passed,
        ),
    ],
    measurements: [
      for (final measurement in observations.measurements)
        (
          source: measurement.source,
          category: measurement.category,
          route: routeOf(measurement.route),
          metric: measurement.metric,
          weight: measurement.weight,
          toolScore: measurement.toolScore,
        ),
    ],
  );
}

Finding _normalizeFinding(Finding finding, String route, String? target) => (
  fingerprint: fingerprint(
    source: finding.source,
    rule: finding.rule,
    route: route,
    target: target,
  ),
  source: finding.source,
  category: finding.category,
  severity: finding.severity,
  rule: finding.rule,
  route: route,
  target: target,
  message: finding.message,
  metric: finding.metric,
);

Finding _withSeverity(Finding finding, Severity severity) => (
  fingerprint: finding.fingerprint,
  source: finding.source,
  category: finding.category,
  severity: severity,
  rule: finding.rule,
  route: finding.route,
  target: finding.target,
  message: finding.message,
  metric: finding.metric,
);

Severity _mostSevere(Severity left, Severity right) =>
    left.index <= right.index ? left : right;

typedef _OutcomeKey = (Source, Category, String, String);

/// Collapses duplicates that the same tool reported more than once.
///
/// Findings with one fingerprint become the first one seen, at the highest
/// severity seen. Rule outcomes for one source, category, rule, and route
/// become one that passed only if all passed, at the largest weight.
/// Measurements are kept as they are. First-seen order is kept.
Observations dedupe(Observations observations) {
  final findings = <String, Finding>{};
  for (final finding in observations.findings) {
    findings.update(
      finding.fingerprint,
      (seen) =>
          _withSeverity(seen, _mostSevere(seen.severity, finding.severity)),
      ifAbsent: () => finding,
    );
  }
  final outcomes = <_OutcomeKey, RuleOutcome>{};
  for (final outcome in observations.ruleOutcomes) {
    outcomes.update(
      (outcome.source, outcome.category, outcome.rule, outcome.route),
      (seen) => (
        source: seen.source,
        category: seen.category,
        rule: seen.rule,
        route: seen.route,
        weight: seen.weight >= outcome.weight ? seen.weight : outcome.weight,
        passed: seen.passed && outcome.passed,
      ),
      ifAbsent: () => outcome,
    );
  }
  return (
    findings: List.unmodifiable(findings.values),
    ruleOutcomes: List.unmodifiable(outcomes.values),
    measurements: List.unmodifiable(observations.measurements),
  );
}
