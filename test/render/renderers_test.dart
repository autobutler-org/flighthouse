import 'dart:convert';
import 'dart:io';

import 'package:flighthouse/flighthouse.dart';
import 'package:flighthouse/src/render/html_renderer.dart'
    show
        displayScore,
        escapeHtml,
        formatNumber,
        formatValue,
        metricTitle,
        readableTimestamp,
        scoreBand;
import 'package:test/test.dart';

import '../model/samples.dart';

const goldenDir = 'test/fixtures/render';
final updateGoldens = Platform.environment['FLIGHTHOUSE_UPDATE_GOLDENS'] == '1';

double? scoreWithoutConfig(Measurement measurement) =>
    measurementScore(measurement, const {});

void expectGolden(String name, String actual) {
  final file = File('$goldenDir/$name');
  if (updateGoldens) {
    file.writeAsStringSync(actual);
  }
  expect(actual, file.readAsStringSync(), reason: 'golden $name is stale');
}

Finding withMessage(Finding finding, String message) => (
  fingerprint: finding.fingerprint,
  source: finding.source,
  category: finding.category,
  severity: finding.severity,
  rule: finding.rule,
  route: finding.route,
  target: finding.target,
  message: message,
  metric: finding.metric,
);

BaselineDiff sampleDiff(Report report) {
  final baseline = baselineOf(
    sampleReport(findings: [slowFrameFinding, fixedFinding]),
  );
  return diffAgainstBaseline(
    report,
    baseline,
    baselinePath: 'flighthouse-baseline.json',
  ).fold((diff) => diff, (failure) => fail('$failure'));
}

final Finding fixedFinding = (
  fingerprint: fingerprintOf('fixed-label'),
  source: Source.axe,
  category: Category.a11y,
  severity: Severity.critical,
  rule: 'button-name',
  route: '/settings',
  target: null,
  message: 'Buttons must have discernible text',
  metric: null,
);

const Measurement insightMeasurement = (
  source: Source.lighthouse,
  category: Category.perf,
  route: '/login',
  metric: (name: 'cache-insight', value: 0, unit: MetricUnit.score),
  weight: 0,
  toolScore: 0,
);

const Measurement byteMeasurement = (
  source: Source.lighthouse,
  category: Category.perf,
  route: '/login',
  metric: (name: 'total-byte-weight', value: 1572864, unit: MetricUnit.bytes),
  weight: 0,
  toolScore: 0.95,
);

void main() {
  final report = sampleReport();

  group('renderJson', () {
    test('is the canonical JSON, indented, with a trailing newline', () {
      final rendered = renderJson(report);
      expect(rendered, endsWith('}\n'));
      expect(rendered, contains('\n  "schemaVersion": 1,'));
      expect(jsonDecode(rendered), reportToJson(report));
    });

    test('matches its golden', () {
      expectGolden('report.json', renderJson(report));
    });
  });

  group('renderHtml', () {
    final html = renderHtml(report, measurementScoreOf: scoreWithoutConfig);
    final withDiff = renderHtml(
      report,
      diff: sampleDiff(report),
      measurementScoreOf: scoreWithoutConfig,
    );

    test('is a complete document with a language', () {
      expect(html, startsWith('<!doctype html>\n<html lang="en">'));
      expect(html, contains('<title>quark flighthouse report</title>'));
      expect(html, endsWith('</html>\n'));
    });

    test('loads nothing external and runs no script', () {
      for (final document in [html, withDiff]) {
        expect(document, isNot(contains('<script')));
        expect(document, isNot(contains('<link')));
        expect(document, isNot(contains('src=')));
        expect(document, isNot(contains('href=')));
        expect(document, isNot(contains('@import')));
        expect(document, isNot(contains('url(')));
      }
    });

    test('labels every gauge with text, not color alone', () {
      expect(
        html,
        contains(
          '<span class="visually-hidden">Overall score: </span>80</span>',
        ),
      );
      expect(
        html,
        contains(
          '<span class="visually-hidden">Accessibility score: </span>82</span>',
        ),
      );
      expect(
        html,
        contains('<span class="visually-hidden">Memory score: </span>n/a'),
      );
      expect(RegExp('<svg[^>]*aria-hidden="true"').allMatches(html).length, 6);
    });

    test('says which categories were not measured', () {
      expect(
        html,
        contains(
          'Not measured, so left out of the overall score: '
          'Memory, Best practices.',
        ),
      );
    });

    test('escapes everything that came from tools or config', () {
      final hostile = renderHtml(
        sampleReport(
          findings: [
            withMessage(contrastFinding, '<img src=x onerror=alert(1)>&"'),
          ],
        ),
        measurementScoreOf: scoreWithoutConfig,
      );
      expect(hostile, isNot(contains('<img')));
      expect(
        hostile,
        contains('&lt;img src=x onerror=alert(1)&gt;&amp;&quot;'),
      );
      expect(hostile, contains('flt-semantics[role=&quot;button&quot;]'));
    });

    test('groups findings by category and severity', () {
      expect(html, contains('<h3>Accessibility (1)</h3>'));
      expect(html, contains('<summary>Serious (1)</summary>'));
      expect(html, contains('<h3>Responsiveness (1)</h3>'));
      expect(html, contains('<summary>Moderate (1)</summary>'));
      expect(
        html,
        contains('<p class="detail">frame_build_time_p90: 12.5 ms</p>'),
      );
    });

    test('marks unscored measurements', () {
      expect(html, contains('<td>12.5 ms</td><td>not scored</td>'));
      expect(html, contains('<td>1,800 ms</td><td>92</td>'));
    });

    test('without a diff there is no baseline section or new badge', () {
      expect(html, isNot(contains('Compared with the baseline')));
      expect(html, isNot(contains('class="badge new"')));
    });

    test('with a diff it flags new findings and lists fixed ones', () {
      expect(withDiff, contains('Compared with the baseline'));
      expect(withDiff, contains('<li><strong>1</strong> new</li>'));
      expect(withDiff, contains('<li><strong>1</strong> fixed</li>'));
      expect(withDiff, contains('<li><strong>1</strong> unchanged</li>'));
      expect('class="badge new"'.allMatches(withDiff).length, 1);
      expect(withDiff, contains('Fixed since the baseline (1)'));
      expect(withDiff, contains('flighthouse baseline --update'));
      expect(
        withDiff,
        contains(
          '<tr><th scope="row">Overall</th><td>80 to 80 (no change)</td></tr>',
        ),
      );
    });

    test('does not depend on finding order', () {
      expect(
        renderHtml(
          sampleReport(findings: [slowFrameFinding, contrastFinding]),
          measurementScoreOf: scoreWithoutConfig,
        ),
        html,
      );
    });

    test('says so when there are no findings', () {
      expect(
        renderHtml(
          sampleReport(findings: const []),
          measurementScoreOf: scoreWithoutConfig,
        ),
        contains('<p>No findings.</p>'),
      );
    });

    test('keeps a multi-line message as a headline and its details', () {
      final multiLine = renderHtml(
        sampleReport(
          findings: [
            withMessage(contrastFinding, 'Fix this\nFirst reason\n<b>el'),
          ],
        ),
        measurementScoreOf: scoreWithoutConfig,
      );
      expect(
        multiLine,
        contains(
          '<p class="message">Fix this</p>'
          '<pre class="message-detail">First reason\n&lt;b&gt;el</pre>',
        ),
      );
      expect(
        html,
        contains('<p class="message">${contrastFinding.message}</p>'),
      );
      expect(html, isNot(contains('<pre class="message-detail">')));
    });

    test('explains the score scale, the bands, and each category', () {
      expect(html, contains('Scores run from 0 to 100'));
      expect(html, contains('<span class="badge band-pass">90 to 100</span>'));
      expect(
        html,
        contains('<span class="badge band-average">50 to 89</span>'),
      );
      expect(html, contains('<span class="badge band-fail">0 to 49</span>'));
      expect(
        html,
        contains(
          '<dt>Accessibility</dt><dd>Whether people who use a screen reader',
        ),
      );
      expect(html, contains('Measured by axe in this run.</dd>'));
      expect(html, contains('<dt>Memory</dt><dd>'));
      expect(html, contains('Not measured in this run.</dd>'));
    });

    test('says what each tool that fed the report measures', () {
      expect(
        html,
        contains('<li><strong>axe</strong> 4.10.3: accessibility rules'),
      );
      expect(html, contains('<li><strong>Lighthouse</strong> 12.8.0: '));
      expect(html, contains('Feeds Performance.</li>'));
    });

    test('explains needs-review results and the baseline terms', () {
      expect(html, contains('Needs review'));
      expect(html, contains('do not lower the score'));
      expect(withDiff, contains('The baseline is'));
      expect(withDiff, contains('<dt>Unchanged</dt>'));
    });

    test('shows the timestamp as a readable date', () {
      expect(
        html,
        contains(
          '<time datetime="2026-10-06T19:30:00.000Z">'
          '6 October 2026, 19:30 UTC</time>',
        ),
      );
    });

    test('titles measurements and lists the worst score first', () {
      final measured = renderHtml(
        sampleReport(
          measurements: [
            lcpMeasurement,
            frameMeasurement,
            insightMeasurement,
            byteMeasurement,
          ],
        ),
        measurementScoreOf: scoreWithoutConfig,
      );
      final rows = RegExp('<tr><td>([^<]*)<br><code>')
          .allMatches(measured)
          .map((match) => match.group(1))
          .toList();
      expect(rows, [
        'Cache insight',
        'Largest contentful paint',
        'Total byte weight',
        'Frame build time p90',
      ]);
      expect(measured, contains('<td>0 of 100</td><td>0</td>'));
      expect(measured, contains('<td>1,800 ms</td><td>92</td>'));
      expect(measured, contains('<td>1.5 MiB</td>'));
    });

    test('wraps every table so it scrolls on its own', () {
      for (final document in [html, withDiff]) {
        expect(
          '<table'.allMatches(document).length,
          '<div class="table-wrap" role="region" tabindex="0"'
              .allMatches(document)
              .length,
        );
      }
    });

    test('prints every section, including closed groups', () {
      expect(html, contains('@media print'));
      expect(html, contains('::details-content'));
    });

    test('matches its goldens', () {
      expectGolden('report.html', html);
      expectGolden('report-with-baseline.html', withDiff);
    });
  });

  group('helpers', () {
    test('score bands follow Lighthouse', () {
      expect(scoreBand(1), 'pass');
      expect(scoreBand(0.9), 'pass');
      expect(scoreBand(0.89), 'average');
      expect(scoreBand(0.5), 'average');
      expect(scoreBand(0.49), 'fail');
      expect(scoreBand(null), 'none');
    });

    test('scores display as rounded points', () {
      expect(displayScore(0.924), 92);
      expect(displayScore(0.926), 93);
      expect(displayScore(1), 100);
    });

    test('numbers group thousands and drop trailing zeros', () {
      expect(formatNumber(1234567), '1,234,567');
      expect(formatNumber(12.5), '12.5');
      expect(formatNumber(0.125), '0.13');
      expect(formatNumber(2.004), '2');
      expect(formatNumber(999), '999');
    });

    test('values read in their unit', () {
      expect(
        formatValue((name: 'x', value: 512, unit: MetricUnit.bytes)),
        '512 bytes',
      );
      expect(
        formatValue((name: 'x', value: 2048, unit: MetricUnit.bytes)),
        '2 KiB',
      );
      expect(
        formatValue((name: 'x', value: 1, unit: MetricUnit.score)),
        '100 of 100',
      );
      expect(
        formatValue((name: 'x', value: 100, unit: MetricUnit.count)),
        '100',
      );
      expect(
        formatValue((name: 'x', value: 0.25, unit: MetricUnit.ratio)),
        '0.25',
      );
    });

    test('metric ids become sentence-case titles', () {
      expect(
        metricTitle('largest-contentful-paint'),
        'Largest contentful paint',
      );
      expect(metricTitle('frame_build_time_p90'), 'Frame build time p90');
      expect(metricTitle('--'), '--');
    });

    test('timestamps read as a UTC date and time', () {
      expect(
        readableTimestamp(DateTime.utc(2026, 1, 2, 3, 4)),
        '2 January 2026, 03:04 UTC',
      );
    });

    test('escapeHtml escapes markup and quotes', () {
      expect(escapeHtml('<a href="x">\'&</a>'), isNot(contains('<')));
      expect(escapeHtml('a & b'), 'a &amp; b');
    });
  });
}
