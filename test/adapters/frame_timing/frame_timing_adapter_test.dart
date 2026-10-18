import 'dart:convert';
import 'dart:io';

import 'package:flighthouse/flighthouse.dart';
import 'package:test/test.dart';

const fixtures = 'test/fixtures/timeline/3.47.7';

const control = 'perf-control.frame_timing_summary.json';
const janky = 'perf-janky.frame_timing_summary.json';

String fixture(String name) => File('$fixtures/$name').readAsStringSync();

Map<String, Object?> fixtureJson(String name) =>
    jsonDecode(fixture(name)) as Map<String, Object?>;

AdapterOutput parsed(String name) => parseFrameTiming((
  source: Source.timeline,
  path: 'build/flighthouse/timeline/$name',
  contents: fixture(name),
)).fold((output) => output, (failure) => fail('$failure'));

String failureOf(
  Object? json, {
  String path = 'traces/login.frame_timing_summary.json',
}) => parseFrameTiming((
  source: Source.timeline,
  path: path,
  contents: json is String ? json : jsonEncode(json),
)).fold((_) => fail('expected a failure'), describe);

Map<String, Object?> controlWith(Map<String, Object?> changes) => {
  ...fixtureJson(control),
  ...changes,
};

Map<String, Severity> severities(AdapterOutput output) => {
  for (final finding in output.findings) finding.rule: finding.severity,
};

Severity mostSevere(AdapterOutput output) => output.findings
    .map((finding) => finding.severity)
    .reduce((left, right) => left.index <= right.index ? left : right);

Map<String, double> metrics(AdapterOutput output) => {
  for (final measurement in output.measurements)
    measurement.metric.name: measurement.metric.value,
};

void main() {
  group(control, () {
    final output = parsed(control);

    test('uses the scenario as the route for everything', () {
      expect(
        {
          for (final finding in output.findings) finding.route,
          for (final measurement in output.measurements) measurement.route,
        },
        {'perf-control'},
      );
    });

    test('measures build and raster times and missed budgets', () {
      expect(metrics(output), {
        'average_frame_build_time_millis': 18.3,
        '90th_percentile_frame_build_time_millis': 26.3,
        '99th_percentile_frame_build_time_millis': 26.3,
        'worst_frame_build_time_millis': 26.3,
        'average_frame_rasterizer_time_millis': 24.5,
        '90th_percentile_frame_rasterizer_time_millis': 37.9,
        '99th_percentile_frame_rasterizer_time_millis': 37.9,
        'worst_frame_rasterizer_time_millis': 37.9,
        'missed_frame_build_budget_count': 1,
        'missed_frame_rasterizer_budget_count': 1,
      });
    });

    test('every measurement is responsiveness without a tool score', () {
      expect(
        {
          for (final measurement in output.measurements)
            (measurement.category, measurement.toolScore, measurement.weight),
        },
        {(Category.responsiveness, null, 1.0)},
      );
    });

    test('units are milliseconds for times and counts for budgets', () {
      expect({
        for (final measurement in output.measurements)
          measurement.metric.name: measurement.metric.unit,
      }, containsPair('missed_frame_build_budget_count', MetricUnit.count));
      expect({
        for (final measurement in output.measurements)
          measurement.metric.name: measurement.metric.unit,
      }, containsPair('worst_frame_build_time_millis', MetricUnit.ms));
    });

    test('averages just over budget are moderate findings', () {
      expect(severities(output), {
        'frame-build-budget': Severity.moderate,
        'frame-rasterizer-budget': Severity.moderate,
      });
    });

    test('a finding names its frames, budget, and average', () {
      final finding = output.findings.firstWhere(
        (finding) => finding.rule == 'frame-build-budget',
      );
      expect(
        finding.message,
        '1 of 2 frames missed the 16 ms build budget; '
        'the average build time was 18.3 ms',
      );
      expect(finding.metric?.name, 'average_frame_build_time_millis');
      expect(finding.target, isNull);
      expect(finding.category, Category.responsiveness);
    });

    test('has no rule outcomes and an unknown tool version', () {
      expect(output.ruleOutcomes, isEmpty);
      expect(output.toolVersion, 'unknown');
    });
  });

  group(janky, () {
    final output = parsed(janky);

    test('a build time several budgets over is critical', () {
      expect(severities(output), {
        'frame-build-budget': Severity.critical,
        'frame-rasterizer-budget': Severity.minor,
      });
    });

    test('measures the slow build times', () {
      expect(
        metrics(output),
        containsPair('missed_frame_build_budget_count', 17),
      );
      expect(
        metrics(output),
        containsPair('average_frame_build_time_millis', 124.494),
      );
    });

    test('the build finding counts every frame', () {
      expect(
        output.findings
            .firstWhere((finding) => finding.rule == 'frame-build-budget')
            .message,
        startsWith('17 of 17 frames missed the 16 ms build budget'),
      );
    });

    test('is more severe than the control', () {
      expect(
        mostSevere(output).index,
        lessThan(mostSevere(parsed(control)).index),
      );
    });

    test('scores lower than the control on build time control points', () {
      double? responsiveness(AdapterOutput output) => score(
        ruleOutcomes: output.ruleOutcomes,
        measurements: output.measurements,
        scoring: ScoringConfig(
          weights: defaultCategoryWeights,
          metrics: const {
            'average_frame_build_time_millis': (p10: 8, median: 16),
          },
        ),
      ).categories[Category.responsiveness];
      expect(
        responsiveness(output),
        lessThan(responsiveness(parsed(control))!),
      );
    });
  });

  group('severity', () {
    test('steps at one, two, and four budgets', () {
      expect(severityOfAverage(16, 0), isNull);
      expect(severityOfAverage(16, 1), Severity.minor);
      expect(severityOfAverage(16.1, 0), Severity.moderate);
      expect(severityOfAverage(32.1, 0), Severity.serious);
      expect(severityOfAverage(64.1, 0), Severity.critical);
    });

    test('a phase within budget with no misses has no finding', () {
      final output = parseFrameTiming((
        source: Source.timeline,
        path: control,
        contents: jsonEncode(
          controlWith({
            'average_frame_rasterizer_time_millis': 10,
            'missed_frame_rasterizer_budget_count': 0,
          }),
        ),
      )).fold((output) => output, (failure) => fail('$failure'));
      expect(severities(output).keys, ['frame-build-budget']);
    });
  });

  group('malformed input', () {
    test('invalid JSON', () {
      expect(failureOf('{nope'), contains('not valid JSON'));
    });

    test('a root that is not an object', () {
      expect(failureOf(<Object>[]), contains(r'$'));
    });

    test('a missing measured key names its path', () {
      expect(
        failureOf(
          fixtureJson(control)..remove('average_frame_build_time_millis'),
        ),
        contains(r'$.average_frame_build_time_millis'),
      );
    });

    test('a missing unmeasured key names its path', () {
      expect(
        failureOf(fixtureJson(control)..remove('old_gen_gc_count')),
        contains(r'$.old_gen_gc_count'),
      );
    });

    test('a time of the wrong type names its path', () {
      expect(
        failureOf(controlWith({'worst_frame_rasterizer_time_millis': '37.9'})),
        contains(r'$.worst_frame_rasterizer_time_millis'),
      );
    });

    test('a negative time names its path', () {
      expect(
        failureOf(controlWith({'average_frame_build_time_millis': -1})),
        contains(r'$.average_frame_build_time_millis'),
      );
    });

    test('a fractional missed count names its path', () {
      expect(
        failureOf(controlWith({'missed_frame_build_budget_count': 1.5})),
        contains(r'$.missed_frame_build_budget_count'),
      );
    });

    test('a bad frame time in a list names its index', () {
      expect(
        failureOf(
          controlWith({
            'frame_build_times': [26300, 'x'],
          }),
        ),
        contains(r'$.frame_build_times[1]'),
      );
    });

    test('a GC count of the wrong type names its path', () {
      expect(
        failureOf(controlWith({'new_gen_gc_count': null})),
        contains(r'$.new_gen_gc_count'),
      );
    });

    test('a key outside the tested summary is refused', () {
      expect(
        failureOf(controlWith({'average_vsync_overhead_millis': 1})),
        contains('average_vsync_overhead_millis'),
      );
    });

    test('the failure names the tool and the artifact', () {
      final failure =
          parseFrameTiming((
                source: Source.timeline,
                path: 'traces/x.frame_timing_summary.json',
                contents: '{}',
              )).fold((_) => fail('expected a failure'), (failure) => failure)
              as AdapterFailure;
      expect(failure.tool, 'timeline');
      expect(failure.artifactPath, 'traces/x.frame_timing_summary.json');
    });
  });

  group('file names', () {
    test('a TimelineSummary file is not read yet', () {
      expect(
        failureOf(
          fixtureJson(control),
          path: 'traces/login.timeline_summary.json',
        ),
        contains('TimelineSummary output is not read yet'),
      );
    });

    test('any other JSON file is refused by name', () {
      expect(
        failureOf(
          fixtureJson(control),
          path: 'traces/integration_response_data.json',
        ),
        contains('integration_response_data.json is not named'),
      );
    });

    test('a suffix with no scenario is refused', () {
      expect(
        failureOf(
          fixtureJson(control),
          path: 'traces/$frameTimingSummarySuffix',
        ),
        contains('is not named'),
      );
    });

    test('a Windows path still yields the scenario', () {
      final output = parseFrameTiming((
        source: Source.timeline,
        path: r'build\timeline\' + control,
        contents: fixture(control),
      )).fold((output) => output, (failure) => fail('$failure'));
      expect(output.findings.first.route, 'perf-control');
    });
  });
}

Severity? severityOfAverage(double average, double missed) =>
    parseFrameTiming((
      source: Source.timeline,
      path: control,
      contents: jsonEncode(
        controlWith({
          'average_frame_build_time_millis': average,
          'missed_frame_build_budget_count': missed.toInt(),
          'average_frame_rasterizer_time_millis': 1,
          'missed_frame_rasterizer_budget_count': 0,
        }),
      ),
    )).fold(
      (output) => severities(output)['frame-build-budget'],
      (failure) => fail('$failure'),
    );
