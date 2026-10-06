import 'enums.dart';

/// A named measured value, such as a frame build time.
typedef Metric = ({String name, double value, MetricUnit unit});

/// A failure a human acts on and the baseline tracks.
///
/// [fingerprint] identifies the finding across runs; [message] is not part of
/// it, so rewording a message does not make a finding new.
typedef Finding = ({
  Source source,
  Category category,
  Severity severity,
  String rule,
  String route,
  String? target,
  String fingerprint,
  String message,
  Metric? metric,
});

/// One rule a tool checked on one route, whether it passed or not.
///
/// Rule scores are the weighted share of outcomes that passed.
typedef RuleOutcome = ({
  Source source,
  Category category,
  String rule,
  String route,
  double weight,
  bool passed,
});

/// A metric measured on one route, with the tool's own score when it has one.
typedef Measurement = ({
  Source source,
  Category category,
  String route,
  Metric metric,
  double? toolScore,
});
