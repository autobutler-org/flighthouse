import 'dart:convert';
import 'dart:math' as math;

import '../model/baseline.dart';
import '../model/enums.dart';
import '../model/observations.dart';
import '../model/report.dart';
import '../pipeline/diff.dart';

const _escape = HtmlEscape();

String escapeHtml(String text) => _escape.convert(text);

String categoryTitle(Category category) => switch (category) {
  Category.a11y => 'Accessibility',
  Category.perf => 'Performance',
  Category.responsiveness => 'Responsiveness',
  Category.memory => 'Memory',
  Category.bestPractices => 'Best practices',
};

String severityTitle(Severity severity) => switch (severity) {
  Severity.critical => 'Critical',
  Severity.serious => 'Serious',
  Severity.moderate => 'Moderate',
  Severity.minor => 'Minor',
  Severity.info => 'Info',
};

int displayScore(double score) => (score * 100).round();

String scoreBand(double? score) => switch (score) {
  null => 'none',
  final value when value >= 0.9 => 'pass',
  final value when value >= 0.5 => 'average',
  _ => 'fail',
};

String sourceTitle(Source source) => switch (source) {
  Source.attest => 'attest',
  Source.lighthouse => 'Lighthouse',
  Source.axe => 'axe',
  Source.timeline => 'integration_test timeline',
  Source.flutterLighthouse => 'flutter_lighthouse',
};

String _sourceDescription(Source source) => switch (source) {
  Source.attest =>
    'accessibility checks on the Flutter semantics tree, run from tests.',
  Source.lighthouse =>
    "Google's page audit, run in Chrome, for load performance, "
        'best practices, and accessibility.',
  Source.axe =>
    'accessibility rules checked in the browser on the rendered '
        'page.',
  Source.timeline =>
    'frame build and raster times recorded by '
        'integration_test.',
  Source.flutterLighthouse => 'Flutter performance audits.',
};

String _categoryDescription(Category category) => switch (category) {
  Category.a11y =>
    'Whether people who use a screen reader, keyboard, or other assistive '
        'technology can use the app.',
  Category.perf => 'How quickly the page loads and becomes usable.',
  Category.responsiveness =>
    'How smoothly frames render and how fast the app reacts to input.',
  Category.memory => 'How much memory the app uses.',
  Category.bestPractices =>
    'General web practices such as HTTPS, console errors, and deprecated '
        'APIs.',
};

final _thousands = RegExp(r'\B(?=(\d{3})+(?!\d))');

final _trailingZeros = RegExp(r'\.?0+$');

String formatNumber(double value) {
  final fixed = value.toStringAsFixed(2);
  final point = fixed.indexOf('.');
  final whole = point < 0 ? fixed : fixed.substring(0, point);
  final fraction = point < 0 ? '' : fixed.substring(point);
  return '${whole.replaceAllMapped(_thousands, (_) => ',')}'
      '${fraction.replaceFirst(_trailingZeros, '')}';
}

const _kibibyte = 1024;

String _formatBytes(double bytes) => switch (bytes) {
  final value when value < _kibibyte => '${formatNumber(value)} bytes',
  final value when value < _kibibyte * _kibibyte =>
    '${formatNumber((value / _kibibyte * 10).round() / 10)} KiB',
  final value =>
    '${formatNumber((value / (_kibibyte * _kibibyte) * 10).round() / 10)} MiB',
};

String formatValue(Metric metric) => switch (metric.unit) {
  MetricUnit.ms => '${formatNumber(metric.value)} ms',
  MetricUnit.bytes => _formatBytes(metric.value),
  MetricUnit.count || MetricUnit.ratio => formatNumber(metric.value),
  MetricUnit.score => '${displayScore(metric.value)} of 100',
};

String metricTitle(String name) {
  final words = name.split(RegExp('[-_]+')).where((word) => word.isNotEmpty);
  final title = words.join(' ');
  return title.isEmpty
      ? name
      : '${title[0].toUpperCase()}${title.substring(1)}';
}

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _twoDigits(int value) => '$value'.padLeft(2, '0');

String readableTimestamp(DateTime timestamp) {
  final utc = timestamp.toUtc();
  return '${utc.day} ${_months[utc.month - 1]} ${utc.year}, '
      '${_twoDigits(utc.hour)}:${_twoDigits(utc.minute)} UTC';
}

String _inWords(List<String> items) => switch (items) {
  [] => '',
  [final only] => only,
  [...final first, final last] => '${first.join(', ')} and $last',
};

String _tableWrap(String label, String table) =>
    '<div class="table-wrap" role="region" tabindex="0" '
    'aria-label="${escapeHtml(label)}">$table</div>';

const _gaugeRadius = 52.0;
const _gaugeCircumference = 2 * math.pi * _gaugeRadius;

String gauge(String label, double? score) {
  final shown = switch (score) {
    final value? => '${displayScore(value)}',
    null => 'n/a',
  };
  final arc = switch (score) {
    final value? =>
      '<circle class="gauge-arc" cx="60" cy="60" r="$_gaugeRadius" '
          'stroke-dasharray="${(value * _gaugeCircumference).toStringAsFixed(2)} '
          '${_gaugeCircumference.toStringAsFixed(2)}" '
          'transform="rotate(-90 60 60)"/>',
    null => '',
  };
  return '<li class="gauge band-${scoreBand(score)}">'
      '<div class="gauge-dial">'
      '<svg viewBox="0 0 120 120" aria-hidden="true" focusable="false">'
      '<circle class="gauge-track" cx="60" cy="60" r="$_gaugeRadius"/>'
      '$arc</svg>'
      '<span class="gauge-score">'
      '<span class="visually-hidden">${escapeHtml(label)} score: </span>'
      '$shown</span></div>'
      '<span class="gauge-label" aria-hidden="true">${escapeHtml(label)}</span>'
      '</li>';
}

Map<Category, List<Source>> _sourcesByCategory(Report report) {
  final fed = {
    for (final finding in report.findings) (finding.category, finding.source),
    for (final outcome in report.ruleOutcomes)
      (outcome.category, outcome.source),
    for (final measurement in report.measurements)
      (measurement.category, measurement.source),
  };
  return {
    for (final category in Category.values)
      category: [
        for (final source in Source.values)
          if (fed.contains((category, source))) source,
      ],
  };
}

String _categoryLegend(Map<Category, List<Source>> sources) =>
    '<dl class="legend">${[
      for (final MapEntry(key: category, value: fedBy) in sources.entries) '<dt>${categoryTitle(category)}</dt><dd>${_categoryDescription(category)} '
            '${fedBy.isEmpty ? 'Not measured in this run.' : 'Measured by ${escapeHtml(_inWords([for (final source in fedBy) sourceTitle(source)]))} in this run.'}</dd>',
    ].join()}</dl>';

String _sourceItem(
  Source source,
  String? version,
  Map<Category, List<Source>> sources,
) {
  final fed = [
    for (final MapEntry(key: category, value: fedBy) in sources.entries)
      if (fedBy.contains(source)) categoryTitle(category),
  ];
  return '<li><strong>${sourceTitle(source)}</strong>'
      '${version == null ? '' : ' ${escapeHtml(version)}'}: '
      '${_sourceDescription(source)} '
      '${fed.isEmpty ? 'Feeds no category in this run.' : 'Feeds ${_inWords(fed)}.'}</li>';
}

String _sourceLegend(
  Map<Source, String> toolVersions,
  Map<Category, List<Source>> sources,
) {
  final items = [
    for (final source in Source.values)
      if (toolVersions.containsKey(source) ||
          sources.values.any((fedBy) => fedBy.contains(source)))
        _sourceItem(source, toolVersions[source], sources),
  ];
  return items.isEmpty
      ? ''
      : '<p>Where the numbers come from:</p>'
            '<ul class="sources">${items.join()}</ul>';
}

String _scoresSection(Report report) {
  final scores = report.scores;
  final sources = _sourcesByCategory(report);
  final unmeasured = [
    for (final MapEntry(:key, :value) in scores.categories.entries)
      if (value == null) categoryTitle(key),
  ];
  return '<section aria-labelledby="scores-heading">'
      '<h2 id="scores-heading">Scores</h2>'
      '<ul class="gauges">'
      '${gauge('Overall', scores.overall)}'
      '${[for (final MapEntry(:key, :value) in scores.categories.entries) gauge(categoryTitle(key), value)].join()}'
      '</ul>'
      '${unmeasured.isEmpty ? '' : '<p class="note">Not measured, so left out of the overall score: ${escapeHtml(unmeasured.join(', '))}.</p>'}'
      '<h3>How to read the scores</h3>'
      '<p>Scores run from 0 to 100, and higher is better. A category score is '
      'the weighted share of its checks that passed and of its measurements '
      'that scored well. The overall score is a weighted average of the '
      'categories that were measured.</p>'
      '<ul class="bands">'
      '<li><span class="badge band-pass">90 to 100</span> good</li>'
      '<li><span class="badge band-average">50 to 89</span> needs improvement</li>'
      '<li><span class="badge band-fail">0 to 49</span> poor</li>'
      '</ul>'
      '${_categoryLegend(sources)}'
      '${_sourceLegend(report.metadata.toolVersions, sources)}'
      '</section>';
}

String _change(ScoreChange change) => switch (change) {
  (baseline: final double before, current: final double after) =>
    '${displayScore(before)} to ${displayScore(after)} '
        '(${switch (displayScore(after) - displayScore(before)) {
          0 => 'no change',
          final delta when delta > 0 => '+$delta',
          final delta => '$delta',
        }})',
  (baseline: final double before, current: null) =>
    '${displayScore(before)} to not measured',
  (baseline: null, current: final double after) =>
    'not measured to ${displayScore(after)}',
  (baseline: null, current: null) => 'not measured',
};

String _diffSection(BaselineDiff diff) =>
    '<section aria-labelledby="baseline-heading">'
    '<h2 id="baseline-heading">Compared with the baseline</h2>'
    '<ul class="counts">'
    '<li><strong>${diff.newFindings.length}</strong> new</li>'
    '<li><strong>${diff.fixedFindings.length}</strong> fixed</li>'
    '<li><strong>${diff.persistingFindings.length}</strong> unchanged</li>'
    '</ul>'
    '<p class="note">The baseline is the set of findings and scores accepted '
    'earlier and saved in the baseline file. This run is compared with it.</p>'
    '<dl class="legend">'
    '<dt>New</dt><dd>Found in this run and not in the baseline.</dd>'
    '<dt>Fixed</dt><dd>In the baseline and no longer found.</dd>'
    '<dt>Unchanged</dt><dd>In the baseline and still found.</dd>'
    '</dl>'
    '${_tableWrap('Score changes', '<table><caption>Score changes</caption>'
        '<thead><tr><th scope="col">Score</th><th scope="col">Baseline to now</th></tr></thead>'
        '<tbody>'
        '<tr><th scope="row">Overall</th><td>${_change(diff.overallScore)}</td></tr>'
        '${[for (final MapEntry(:key, :value) in diff.categoryScores.entries) '<tr><th scope="row">${categoryTitle(key)}</th><td>${_change(value)}</td></tr>'].join()}'
        '</tbody></table>')}'
    '</section>';

int _byLocation(Finding left, Finding right) => switch ((
  left.route.compareTo(right.route),
  left.rule.compareTo(right.rule),
)) {
  (0, 0) => left.fingerprint.compareTo(right.fingerprint),
  (0, final byRule) => byRule,
  (final byRoute, _) => byRoute,
};

String _message(String message) {
  final lineBreak = message.indexOf('\n');
  if (lineBreak < 0) return '<p class="message">${escapeHtml(message)}</p>';
  return '<p class="message">${escapeHtml(message.substring(0, lineBreak))}</p>'
      '<pre class="message-detail">'
      '${escapeHtml(message.substring(lineBreak + 1))}</pre>';
}

String _findingItem(Finding finding, bool isNew) =>
    '<li class="finding">'
    '<p class="finding-head">'
    '<span class="badge severity-${finding.severity.id}">${severityTitle(finding.severity)}</span>'
    '${isNew ? ' <span class="badge new">New</span>' : ''}'
    ' <code>${escapeHtml(finding.rule)}</code> on <code>${escapeHtml(finding.route)}</code>'
    ' <span class="source">from ${escapeHtml(finding.source.id)}</span>'
    '</p>'
    '${_message(finding.message)}'
    '${switch (finding.target) {
      final target? => '<p class="detail">Target: <code>${escapeHtml(target)}</code></p>',
      null => '',
    }}'
    '${switch (finding.metric) {
      final metric? => '<p class="detail">${escapeHtml(metric.name)}: ${formatValue(metric)}</p>',
      null => '',
    }}'
    '</li>';

String _findingsSection(List<Finding> findings, Set<String> newFingerprints) {
  if (findings.isEmpty) {
    return '<section aria-labelledby="findings-heading">'
        '<h2 id="findings-heading">Findings</h2><p>No findings.</p></section>';
  }
  final byCategory = [
    for (final category in Category.values)
      (
        category: category,
        bySeverity: [
          for (final severity in Severity.values)
            (
              severity: severity,
              findings: [
                for (final finding in findings)
                  if (finding.category == category &&
                      finding.severity == severity)
                    finding,
              ]..sort(_byLocation),
            ),
        ].where((group) => group.findings.isNotEmpty).toList(),
      ),
  ].where((group) => group.bySeverity.isNotEmpty);
  return '<section aria-labelledby="findings-heading">'
      '<h2 id="findings-heading">Findings</h2>'
      '<p class="note">Each finding names the rule that failed, the route it '
      'failed on, and the tool that reported it.'
      '${findings.any((finding) => finding.source == Source.axe) ? ' A message that starts with &quot;Needs review&quot; is a check axe '
                'could not decide on its own, so a person has to look at it. '
                'Needs-review results are listed here but do not lower the '
                'score.' : ''}</p>'
      '${[
        for (final group in byCategory) '<h3>${categoryTitle(group.category)} (${group.bySeverity.fold<int>(0, (sum, severity) => sum + severity.findings.length)})</h3>'
              '${[
                for (final severityGroup in group.bySeverity) '<details open><summary>${severityTitle(severityGroup.severity)} (${severityGroup.findings.length})</summary>'
                      '<ul class="findings">${[for (final finding in severityGroup.findings) _findingItem(finding, newFingerprints.contains(finding.fingerprint))].join()}</ul>'
                      '</details>',
              ].join()}',
      ].join()}'
      '</section>';
}

String _fixedSection(List<BaselineFinding> fixed) => fixed.isEmpty
    ? ''
    : '<section aria-labelledby="fixed-heading">'
          '<h2 id="fixed-heading">Fixed since the baseline (${fixed.length})</h2>'
          '<ul class="fixed">${[for (final finding in fixed) '<li><code>${escapeHtml(finding.rule)}</code> on <code>${escapeHtml(finding.route)}</code> <span class="source">from ${escapeHtml(finding.source.id)}</span></li>'].join()}</ul>'
          '<p class="note">Run <code>flighthouse baseline --update</code> to accept these fixes into the baseline.</p>'
          '</section>';

typedef _Scored = ({Measurement measurement, double? score});

int _worstFirst(_Scored left, _Scored right) => switch ((
  left.score,
  right.score,
)) {
  (final double a, final double b) when a != b => a.compareTo(b),
  (null, final double _) => 1,
  (final double _, null) => -1,
  _ => switch (left.measurement.route.compareTo(right.measurement.route)) {
    0 => left.measurement.metric.name.compareTo(right.measurement.metric.name),
    final byRoute => byRoute,
  },
};

String _measurementsSection(
  List<Measurement> measurements,
  double? Function(Measurement measurement) scoreOf,
) {
  if (measurements.isEmpty) return '';
  final scored = [
    for (final measurement in measurements)
      (measurement: measurement, score: scoreOf(measurement)),
  ]..sort(_worstFirst);
  return '<section aria-labelledby="measurements-heading">'
      '<h2 id="measurements-heading">Measurements</h2>'
      '<p class="note">Every value the tools measured, worst score first. A '
      'score is from 0 to 100, either the tool&#39;s own or one computed from '
      'the configured thresholds. A value that is not scored does not count '
      'toward a category score.</p>'
      '<details><summary>${measurements.length} measured values</summary>'
      '${_tableWrap('Measurements', '<table><thead><tr>'
          '<th scope="col">Metric</th><th scope="col">Route</th>'
          '<th scope="col">Value</th><th scope="col">Score</th>'
          '</tr></thead><tbody>'
          '${[for (final (:measurement, :score) in scored) '<tr><td>${escapeHtml(metricTitle(measurement.metric.name))}<br><code>${escapeHtml(measurement.metric.name)}</code></td>'
                '<td><code>${escapeHtml(measurement.route)}</code></td>'
                '<td>${formatValue(measurement.metric)}</td>'
                '<td>${switch (score) {
                  final value? => '${displayScore(value)}',
                  null => 'not scored',
                }}</td></tr>'].join()}'
          '</tbody></table>')}</details></section>';
}

String _header(ReportMetadata metadata) =>
    '<header><h1>${escapeHtml(metadata.app)}</h1>'
    '<p class="meta">'
    '${switch (metadata.commit) {
      final commit? => 'Commit <code>${escapeHtml(commit)}</code> · ',
      null => '',
    }}'
    '<time datetime="${metadata.timestamp.toIso8601String()}">${readableTimestamp(metadata.timestamp)}</time>'
    ' · flighthouse ${escapeHtml(metadata.flighthouseVersion)}'
    '</p></header>';

String _footer(ReportMetadata metadata) =>
    '<footer><p>Tools: ${metadata.toolVersions.isEmpty ? 'none recorded' : escapeHtml([for (final MapEntry(:key, :value) in metadata.toolVersions.entries) '${key.id} $value'].join(', '))}.</p></footer>';

const _lightTheme =
    '--bg:#fff;--fg:#1b1b1f;--muted:#55565c;--line:#d9d9de;--panel:#f6f6f8;'
    '--pass:#0a7d32;--average:#a14a00;--fail:#c5221f;--none:#6b6b73;'
    '--track:#e4e4e8';

const _styles =
    '''
:root{$_lightTheme}
@media (prefers-color-scheme:dark){:root{--bg:#18181b;--fg:#ececf0;--muted:#a8a8b3;--line:#3a3a42;--panel:#222227;--pass:#4ade80;--average:#fbbf24;--fail:#f87171;--none:#9a9aa5;--track:#33333a}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
header,main,footer{max-width:960px;margin:0 auto;padding:16px}
header{padding-bottom:0}main{padding-top:0}
h1{margin:0;font-size:1.75rem}
h2{margin-top:2rem;font-size:1.35rem;border-bottom:1px solid var(--line);padding-bottom:.25rem}
h3{font-size:1.1rem}
main>section:first-child>h2{margin-top:.5rem}
.meta,.note,.source,.detail,footer{color:var(--muted)}
code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.9em;overflow-wrap:anywhere}
.gauges{list-style:none;padding:0;display:flex;flex-wrap:wrap;gap:16px}
.gauge{display:flex;flex-direction:column;align-items:center;width:120px}
.gauge-dial{position:relative;width:96px;height:96px}
.gauge-dial svg{width:100%;height:100%}
.gauge-track{fill:none;stroke:var(--track);stroke-width:10}
.gauge-arc{fill:none;stroke:currentColor;stroke-width:10;stroke-linecap:round}
.gauge-score{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;font-size:1.6rem;font-weight:600}
.gauge-label{margin-top:4px;text-align:center}
.band-pass{color:var(--pass)}.band-average{color:var(--average)}.band-fail{color:var(--fail)}.band-none{color:var(--none)}
.counts,.bands{list-style:none;padding:0;display:flex;flex-wrap:wrap;gap:8px 24px}
.legend dt{font-weight:600}.legend dd{margin:0 0 .5rem 0}
.sources{padding-left:1.25rem}
.table-wrap{max-width:100%;overflow-x:auto;margin:1rem 0}
table{border-collapse:collapse;width:100%}
caption{text-align:left;font-weight:600;padding-bottom:.25rem}
th,td{text-align:left;padding:6px 8px;border-bottom:1px solid var(--line)}
details{margin:.5rem 0;background:var(--panel);border-radius:8px;padding:8px 12px}
summary{cursor:pointer;font-weight:600}
.findings,.fixed{padding-left:0;list-style:none}
.finding{border-top:1px solid var(--line);padding:8px 0}
.finding p{margin:.25rem 0}
.message-detail{margin:.25rem 0;white-space:pre-wrap;overflow-wrap:anywhere;font:.85em/1.4 ui-monospace,SFMono-Regular,Menlo,monospace;color:var(--muted)}
.badge{display:inline-block;padding:0 8px;border-radius:999px;font-size:.8rem;font-weight:600;border:1px solid currentColor}
.severity-critical,.severity-serious{color:var(--fail)}.severity-moderate{color:var(--average)}.severity-minor,.severity-info{color:var(--none)}
.new{color:var(--fg);background:var(--panel)}
.visually-hidden{position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap;border:0}
@media print{:root{$_lightTheme}header,main,footer{max-width:none}details{background:none;padding:0}details::details-content{content-visibility:visible;display:block;block-size:auto}.table-wrap{overflow:visible}.finding,tr{break-inside:avoid}}
''';

/// Renders [report] as one self-contained `report.html`.
///
/// Inline CSS and SVG only, with no scripts and no external requests, so it
/// opens offline as a CI artifact. With a [diff], new findings are flagged and
/// a baseline comparison section is added. [measurementScoreOf] supplies the
/// score shown for each measurement, or null when it was not scored.
String renderHtml(
  Report report, {
  BaselineDiff? diff,
  required double? Function(Measurement measurement) measurementScoreOf,
}) {
  final newFingerprints = {
    for (final finding in diff?.newFindings ?? const <Finding>[])
      finding.fingerprint,
  };
  return '<!doctype html>\n'
      '<html lang="en"><head><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width,initial-scale=1">'
      '<title>${escapeHtml(report.metadata.app)} flighthouse report</title>'
      '<style>$_styles</style></head><body>'
      '${_header(report.metadata)}'
      '<main>'
      '${_scoresSection(report)}'
      '${diff == null ? '' : _diffSection(diff)}'
      '${_findingsSection(report.findings, newFingerprints)}'
      '${diff == null ? '' : _fixedSection(diff.fixedFindings)}'
      '${_measurementsSection(report.measurements, measurementScoreOf)}'
      '</main>'
      '${_footer(report.metadata)}'
      '</body></html>\n';
}
