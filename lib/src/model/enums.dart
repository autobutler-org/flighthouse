/// What a finding, rule, or measurement is about.
enum Category {
  /// Accessibility.
  a11y('a11y'),

  /// Load and runtime performance.
  perf('perf'),

  /// Frame timing and input latency.
  responsiveness('responsiveness'),

  /// Memory use.
  memory('memory'),

  /// General best practices.
  bestPractices('best-practices');

  const Category(this.id);

  /// The identifier used in JSON and config.
  final String id;
}

/// How serious a finding is, from axe's impact levels plus [info].
enum Severity {
  /// Blocks users entirely.
  critical('critical'),

  /// Seriously impairs users.
  serious('serious'),

  /// Somewhat impairs users.
  moderate('moderate'),

  /// A minor annoyance.
  minor('minor'),

  /// Informational, never a gate failure.
  info('info');

  const Severity(this.id);

  /// The identifier used in JSON and config.
  final String id;
}

/// The tool that produced a result.
enum Source {
  /// attest_flutter and attest_cli reports.
  attest('attest'),

  /// Lighthouse JSON reports.
  lighthouse('lighthouse'),

  /// axe-core results.
  axe('axe'),

  /// integration_test TimelineSummary output.
  timeline('timeline'),

  /// flutter_lighthouse output.
  flutterLighthouse('flutter-lighthouse');

  const Source(this.id);

  /// The identifier used in JSON and config.
  final String id;
}

/// The unit of a metric value.
enum MetricUnit {
  /// Milliseconds.
  ms('ms'),

  /// Bytes.
  bytes('bytes'),

  /// A plain count.
  count('count'),

  /// A ratio, usually from 0 to 1.
  ratio('ratio'),

  /// A tool's own score from 0 to 1.
  score('score');

  const MetricUnit(this.id);

  /// The identifier used in JSON.
  final String id;
}
