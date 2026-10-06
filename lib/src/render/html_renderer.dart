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

String formatNumber(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2);

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

String _scoresSection(Scores scores) {
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
    '<table><caption>Score changes</caption>'
    '<thead><tr><th scope="col">Score</th><th scope="col">Baseline to now</th></tr></thead>'
    '<tbody>'
    '<tr><th scope="row">Overall</th><td>${_change(diff.overallScore)}</td></tr>'
    '${[for (final MapEntry(:key, :value) in diff.categoryScores.entries) '<tr><th scope="row">${categoryTitle(key)}</th><td>${_change(value)}</td></tr>'].join()}'
    '</tbody></table>'
    '</section>';

int _byLocation(Finding left, Finding right) => switch ((
  left.route.compareTo(right.route),
  left.rule.compareTo(right.rule),
)) {
  (0, 0) => left.fingerprint.compareTo(right.fingerprint),
  (0, final byRule) => byRule,
  (final byRoute, _) => byRoute,
};

String _findingItem(Finding finding, bool isNew) =>
    '<li class="finding">'
    '<p class="finding-head">'
    '<span class="badge severity-${finding.severity.id}">${severityTitle(finding.severity)}</span>'
    '${isNew ? ' <span class="badge new">New</span>' : ''}'
    ' <code>${escapeHtml(finding.rule)}</code> on <code>${escapeHtml(finding.route)}</code>'
    ' <span class="source">from ${escapeHtml(finding.source.id)}</span>'
    '</p>'
    '<p>${escapeHtml(finding.message)}</p>'
    '${switch (finding.target) {
      final target? => '<p class="detail">Target: <code>${escapeHtml(target)}</code></p>',
      null => '',
    }}'
    '${switch (finding.metric) {
      final metric? => '<p class="detail">${escapeHtml(metric.name)}: ${formatNumber(metric.value)} ${escapeHtml(metric.unit.id)}</p>',
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

String _measurementsSection(
  List<Measurement> measurements,
  double? Function(Measurement measurement) scoreOf,
) => measurements.isEmpty
    ? ''
    : '<section aria-labelledby="measurements-heading">'
          '<h2 id="measurements-heading">Measurements</h2>'
          '<details><summary>${measurements.length} measured values</summary>'
          '<table><thead><tr>'
          '<th scope="col">Metric</th><th scope="col">Route</th>'
          '<th scope="col">Value</th><th scope="col">Score</th>'
          '</tr></thead><tbody>'
          '${[for (final measurement in measurements) '<tr><td><code>${escapeHtml(measurement.metric.name)}</code></td>'
                '<td><code>${escapeHtml(measurement.route)}</code></td>'
                '<td>${formatNumber(measurement.metric.value)} ${escapeHtml(measurement.metric.unit.id)}</td>'
                '<td>${switch (scoreOf(measurement)) {
                  final score? => '${displayScore(score)}',
                  null => 'not scored',
                }}</td></tr>'].join()}'
          '</tbody></table></details></section>';

String _header(ReportMetadata metadata) =>
    '<header><h1>${escapeHtml(metadata.app)}</h1>'
    '<p class="meta">'
    '${switch (metadata.commit) {
      final commit? => 'Commit <code>${escapeHtml(commit)}</code> · ',
      null => '',
    }}'
    '<time datetime="${metadata.timestamp.toIso8601String()}">${metadata.timestamp.toIso8601String()}</time>'
    ' · flighthouse ${escapeHtml(metadata.flighthouseVersion)}'
    '</p></header>';

String _footer(ReportMetadata metadata) =>
    '<footer><p>Tools: ${metadata.toolVersions.isEmpty ? 'none recorded' : escapeHtml([for (final MapEntry(:key, :value) in metadata.toolVersions.entries) '${key.id} $value'].join(', '))}.</p></footer>';

const _styles = '''
:root{--bg:#fff;--fg:#1b1b1f;--muted:#55565c;--line:#d9d9de;--panel:#f6f6f8;--pass:#0a7d32;--average:#a14a00;--fail:#c5221f;--none:#6b6b73;--track:#e4e4e8}
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
.counts{list-style:none;padding:0;display:flex;gap:24px}
table{border-collapse:collapse;width:100%;margin:1rem 0}
caption{text-align:left;font-weight:600;padding-bottom:.25rem}
th,td{text-align:left;padding:6px 8px;border-bottom:1px solid var(--line)}
details{margin:.5rem 0;background:var(--panel);border-radius:8px;padding:8px 12px}
summary{cursor:pointer;font-weight:600}
.findings,.fixed{padding-left:0;list-style:none}
.finding{border-top:1px solid var(--line);padding:8px 0}
.finding p{margin:.25rem 0}
.badge{display:inline-block;padding:0 8px;border-radius:999px;font-size:.8rem;font-weight:600;border:1px solid currentColor}
.severity-critical,.severity-serious{color:var(--fail)}.severity-moderate{color:var(--average)}.severity-minor,.severity-info{color:var(--none)}
.new{color:var(--fg);background:var(--panel)}
.visually-hidden{position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap;border:0}
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
      '${_scoresSection(report.scores)}'
      '${diff == null ? '' : _diffSection(diff)}'
      '${_findingsSection(report.findings, newFingerprints)}'
      '${diff == null ? '' : _fixedSection(diff.fixedFindings)}'
      '${_measurementsSection(report.measurements, measurementScoreOf)}'
      '</main>'
      '${_footer(report.metadata)}'
      '</body></html>\n';
}
