import 'dart:io';

import 'package:flighthouse/flighthouse.dart';
import 'package:test/test.dart';

final config = parseConfig(
  'app: quark\nsources:\n  lighthouse: {dir: lh}\n  axe: {dir: axe}\n',
).fold((config) => config, (failure) => throw StateError('$failure'));

RawArtifact lighthouse(String name) => (
  source: Source.lighthouse,
  path: name,
  contents: File('test/fixtures/lighthouse/13.5.0/$name').readAsStringSync(),
);

Assembled assemble(
  List<RawArtifact> artifacts, {
  Map<Source, Adapter> adapters = defaultAdapters,
}) => assembleReport(
  config: config,
  artifacts: artifacts,
  timestamp: DateTime.utc(2026, 10, 6),
  commit: null,
  flighthouseVersion: '0.0.1',
  adapters: adapters,
);

void main() {
  test('builds a scored, normalized report from real artifacts', () {
    final assembled = assemble([
      lighthouse('quark-login.json'),
      lighthouse('a11y-failures.json'),
    ]);
    expect(assembled.failures, isEmpty);
    expect(
      {for (final finding in assembled.report.findings) finding.route},
      {'/login', '/'},
    );
    expect(assembled.report.scores.overall, isNotNull);
    expect(assembled.report.metadata.toolVersions, {
      Source.lighthouse: '13.5.0',
    });
  });

  test('a bad artifact is reported and the good ones still count', () {
    final assembled = assemble([
      lighthouse('quark-login.json'),
      (source: Source.lighthouse, path: 'bad.json', contents: '{nope'),
    ]);
    expect(assembled.failures.single, isA<AdapterFailure>());
    expect(assembled.report.ruleOutcomes, isNotEmpty);
  });

  test('a source without an adapter fails once, naming its directory', () {
    final assembled = assemble([
      (source: Source.axe, path: 'a.json', contents: '{}'),
      (source: Source.axe, path: 'b.json', contents: '{}'),
    ]);
    final failure = assembled.failures.single as AdapterFailure;
    expect(failure.tool, 'axe');
    expect(failure.artifactPath, 'axe');
  });

  test('different tool versions of one source are all recorded', () {
    final assembled = assemble(
      [lighthouse('quark-login.json'), lighthouse('a11y-failures.json')],
      adapters: {
        Source.lighthouse: (artifact) => parseLighthouse(artifact).map(
          (output) => AdapterOutput(
            toolVersion: artifact.path.startsWith('quark')
                ? '13.5.0'
                : '13.4.1',
            findings: output.findings,
            ruleOutcomes: output.ruleOutcomes,
            measurements: output.measurements,
          ),
        ),
      },
    );
    expect(
      assembled.report.metadata.toolVersions[Source.lighthouse],
      '13.4.1, 13.5.0',
    );
  });

  test('nothing to read gives an empty, unscored report', () {
    final assembled = assemble(const []);
    expect(assembled.failures, isEmpty);
    expect(assembled.report.scores.overall, isNull);
  });
}
