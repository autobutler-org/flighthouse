import 'dart:convert';
import 'dart:io';

import 'package:flighthouse/flighthouse.dart';
import 'package:flighthouse/src/render/html_renderer.dart'
    show displayScore, escapeHtml, scoreBand;
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
        contains('<p class="detail">frame_build_time_p90: 12.50 ms</p>'),
      );
    });

    test('marks unscored measurements', () {
      expect(html, contains('<td>12.50 ms</td><td>not scored</td>'));
      expect(html, contains('<td>1800 ms</td><td>92</td>'));
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

    test('escapeHtml escapes markup and quotes', () {
      expect(escapeHtml('<a href="x">\'&</a>'), isNot(contains('<')));
      expect(escapeHtml('a & b'), 'a &amp; b');
    });
  });
}
