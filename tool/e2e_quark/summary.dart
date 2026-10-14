import 'dart:convert';
import 'dart:io';

/// One finished step: its name, its process exit code, and how long it took.
typedef StepResult = ({String name, int exitCode, double seconds});

/// Parses the tab-separated `steps.tsv` the harness appends one line to per step.
List<StepResult> parseSteps(String tsv) => [
  for (final line in const LineSplitter().convert(tsv))
    if (line.trim().isNotEmpty)
      (() {
        final parts = line.split('\t');
        if (parts.length != 3) {
          throw FormatException('expected name<TAB>exit<TAB>seconds', line);
        }
        return (
          name: parts[0],
          exitCode: int.parse(parts[1]),
          seconds: double.parse(parts[2]),
        );
      })(),
];

final _gateCounts = RegExp(r'(\d+) new, (\d+) fixed, (\d+) unchanged');

/// Builds the summary.json value. [report] is report.json when it exists,
/// [ciOutput] the stdout of `flighthouse ci` when it ran.
Map<String, Object?> buildSummary({
  required List<StepResult> results,
  required int exitCode,
  required Map<String, Object?> versions,
  required Map<String, Object?> paths,
  Map<String, Object?>? report,
  String? ciOutput,
}) {
  final failed = results.where((r) => r.exitCode != 0).toList();
  final gate = ciOutput == null ? null : _gateCounts.firstMatch(ciOutput);
  final ci = results.where((r) => r.name == 'ci').firstOrNull;
  return {
    'schemaVersion': 1,
    'exitCode': exitCode,
    'verdict': switch ((ci?.exitCode, failed.isEmpty)) {
      (0, true) => 'passed',
      (1, _) => 'gate-failed',
      _ => 'broken',
    },
    'failedStep': failed.isEmpty ? null : failed.first.name,
    'steps': [
      for (final r in results)
        {'name': r.name, 'exitCode': r.exitCode, 'seconds': r.seconds},
    ],
    'scores': report?['scores'],
    'gate': gate == null
        ? null
        : {
            'new': int.parse(gate.group(1)!),
            'fixed': int.parse(gate.group(2)!),
            'unchanged': int.parse(gate.group(3)!),
          },
    'versions': versions,
    'paths': paths,
  };
}

/// Usage: `dart run tool/e2e_quark/summary.dart RUN_DIR EXIT_CODE VERSIONS_JSON`.
void main(List<String> args) {
  if (args.length != 3) {
    stderr.writeln('usage: summary.dart <runDir> <exitCode> <versionsJson>');
    exit(2);
  }
  final runDir = args[0];
  final stepsFile = File('$runDir/steps.tsv');
  final reportFile = File('$runDir/report/report.json');
  final ciFile = File('$runDir/logs/ci.log');
  final summary = buildSummary(
    results: stepsFile.existsSync()
        ? parseSteps(stepsFile.readAsStringSync())
        : [],
    exitCode: int.parse(args[1]),
    versions: (jsonDecode(args[2]) as Map).cast<String, Object?>(),
    report: reportFile.existsSync()
        ? (jsonDecode(reportFile.readAsStringSync()) as Map)
              .cast<String, Object?>()
        : null,
    ciOutput: ciFile.existsSync() ? ciFile.readAsStringSync() : null,
    paths: {
      'reportHtml': '$runDir/report/report.html',
      'reportJson': reportFile.path,
      'raw': '$runDir/report/raw',
      'logs': '$runDir/logs',
    },
  );
  File('$runDir/summary.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(summary)}\n',
  );
}
