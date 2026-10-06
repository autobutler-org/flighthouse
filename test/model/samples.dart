import 'package:flighthouse/flighthouse.dart';

String fingerprintOf(String seed) => seed.codeUnits
    .map((unit) => unit.toRadixString(16).padLeft(2, '0'))
    .join()
    .padRight(64, '0')
    .substring(0, 64);

const Metric frameBuild = (
  name: 'frame_build_time_p90',
  value: 12.5,
  unit: MetricUnit.ms,
);

final Finding contrastFinding = (
  fingerprint: fingerprintOf('contrast'),
  source: Source.axe,
  category: Category.a11y,
  severity: Severity.serious,
  rule: 'color-contrast',
  route: '/login',
  target: 'flt-semantics[role="button"]',
  message: 'Elements must meet minimum color contrast ratio thresholds',
  metric: null,
);

final Finding slowFrameFinding = (
  fingerprint: fingerprintOf('slow-frame'),
  source: Source.timeline,
  category: Category.responsiveness,
  severity: Severity.moderate,
  rule: 'frame-budget',
  route: '/photos',
  target: null,
  message: 'p90 frame build time exceeds the 16 ms budget',
  metric: frameBuild,
);

const RuleOutcome contrastOutcome = (
  source: Source.axe,
  category: Category.a11y,
  rule: 'color-contrast',
  route: '/login',
  weight: 7,
  passed: false,
);

const RuleOutcome labelOutcome = (
  source: Source.axe,
  category: Category.a11y,
  rule: 'button-name',
  route: '/login',
  weight: 10,
  passed: true,
);

const Measurement lcpMeasurement = (
  source: Source.lighthouse,
  category: Category.perf,
  route: '/login',
  metric: (name: 'largest-contentful-paint', value: 1800, unit: MetricUnit.ms),
  toolScore: 0.92,
);

const Measurement frameMeasurement = (
  source: Source.timeline,
  category: Category.responsiveness,
  route: '/photos',
  metric: frameBuild,
  toolScore: null,
);

ReportMetadata sampleMetadata() => ReportMetadata(
  app: 'quark',
  commit: 'f49bdf18',
  timestamp: DateTime.utc(2026, 10, 6, 19, 30),
  flighthouseVersion: '0.0.1',
  toolVersions: const {Source.lighthouse: '12.8.0', Source.axe: '4.10.3'},
);

Scores sampleScores() => Scores(
  categories: const {
    Category.a11y: 0.82,
    Category.perf: 0.9,
    Category.responsiveness: 0.61,
  },
  overall: 0.8,
);

Report sampleReport({
  List<Finding>? findings,
  List<RuleOutcome>? ruleOutcomes,
  List<Measurement>? measurements,
}) => Report(
  metadata: sampleMetadata(),
  scores: sampleScores(),
  findings: findings ?? [contrastFinding, slowFrameFinding],
  ruleOutcomes: ruleOutcomes ?? const [contrastOutcome, labelOutcome],
  measurements: measurements ?? const [lcpMeasurement, frameMeasurement],
);
