import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../adapters/adapter.dart';
import '../config/config.dart';
import '../config/parse_config.dart';
import '../model/baseline.dart';
import '../model/baseline_json.dart';
import '../model/enums.dart';
import '../model/report.dart';
import '../io/files.dart';
import '../io/git.dart';
import '../pipeline/assemble.dart';
import '../pipeline/baseline_update.dart';
import '../pipeline/diff.dart';
import '../pipeline/gate.dart';
import '../pipeline/scoring.dart';
import '../render/html_renderer.dart';
import '../render/json_renderer.dart';
import '../result/failure.dart';
import '../result/result.dart';

/// The process exit code when every check passed.
const int exitPassed = 0;

/// The process exit code when the CI gate failed.
const int exitGateFailed = 1;

/// The process exit code for a usage or configuration error.
const int exitUsageError = 2;

/// The process exit code for an unusable input or a missing tool.
const int exitInputError = 3;

/// The effects the CLI needs beyond the filesystem, injectable for tests.
typedef CliEnvironment = ({
  DateTime Function() now,
  Future<String?> Function(String directory) commitOf,
  StringSink out,
  StringSink err,
});

/// The real clock, git, and standard streams.
CliEnvironment defaultEnvironment() =>
    (now: DateTime.now, commitOf: currentCommit, out: stdout, err: stderr);

int exitCodeFor(Failure failure) => switch (failure) {
  ConfigFailure() => exitUsageError,
  SchemaFailure() ||
  AdapterFailure() ||
  MissingToolFailure() ||
  IoFailure() ||
  ProcessFailure() ||
  BaselineFailure() => exitInputError,
};

typedef _Context = ({
  Config config,
  String baseDir,
  String reportDir,
  String version,
  CliEnvironment environment,
});

String _resolve(_Context context, String path) =>
    p.isAbsolute(path) ? path : p.normalize(p.join(context.baseDir, path));

String _rawDir(_Context context, Source source) =>
    p.join(context.reportDir, 'raw', source.id);

String formatScore(double? score) => switch (score) {
  final value? => '${displayScore(value)}',
  null => 'n/a',
};

String summaryLine(Report report) => [
  '${report.metadata.app}: overall ${formatScore(report.scores.overall)}',
  for (final MapEntry(:key, :value) in report.scores.categories.entries)
    '${key.id} ${formatScore(value)}',
].join(' | ');

int _reportFailures(List<Failure> failures, CliEnvironment environment) {
  for (final failure in failures) {
    environment.err.writeln(describe(failure));
  }
  return failures.map(exitCodeFor).fold(exitPassed, (worst, code) {
    return code > worst ? code : worst;
  });
}

Future<Result<_Context, Failure>> _load(
  ArgResults global,
  CliEnvironment environment,
  String version,
) async {
  final configPath = global.option('config')!;
  final text = await readText(configPath);
  return switch (text) {
    Err(:final error) => Err(
      ConfigFailure(keyPath: '(file)', problem: describe(error)),
    ),
    Ok(value: final contents) => parseConfig(contents).map((config) {
      final baseDir = p.dirname(configPath);
      return (
        config: config,
        baseDir: baseDir,
        reportDir:
            global.option('report-dir') ??
            p.normalize(p.join(baseDir, config.reportDir)),
        version: version,
        environment: environment,
      );
    }),
  };
}

Future<Result<List<RawArtifact>, Failure>> _readSource(
  _Context context,
  Source source,
) async {
  final directory = _rawDir(context, source);
  if (!await Directory(directory).exists()) {
    return Err(
      IoFailure(
        operation: 'read',
        path: directory,
        reason: 'not found; run flighthouse collect first',
      ),
    );
  }
  final listed = await listJsonFiles(directory);
  switch (listed) {
    case Err(:final error):
      return Err(error);
    case Ok(value: final paths) when paths.isEmpty:
      return Err(
        AdapterFailure(
          tool: source.id,
          artifactPath: directory,
          problem: 'no .json outputs found',
        ),
      );
    case Ok(value: final paths):
      final artifacts = <RawArtifact>[];
      for (final path in paths) {
        switch (await readText(path)) {
          case Ok(value: final contents):
            artifacts.add((source: source, path: path, contents: contents));
          case Err(:final error):
            return Err(error);
        }
      }
      return Ok(List.unmodifiable(artifacts));
  }
}

Future<Assembled> _assemble(_Context context) async {
  final read = <Result<List<RawArtifact>, Failure>>[
    for (final source in context.config.sources.keys)
      await _readSource(context, source),
  ];
  final (artifacts, readFailures) = partition(read);
  final assembled = assembleReport(
    config: context.config,
    artifacts: [for (final batch in artifacts) ...batch],
    timestamp: context.environment.now(),
    commit: await context.environment.commitOf(context.baseDir),
    flighthouseVersion: context.version,
  );
  return (
    report: assembled.report,
    failures: List<Failure>.unmodifiable([
      ...readFailures,
      ...assembled.failures,
    ]),
  );
}

Future<Result<List<String>, Failure>> _writeReport(
  _Context context,
  Report report,
  BaselineDiff? diff,
) async {
  final written = [
    await writeText(
      p.join(context.reportDir, 'report.json'),
      renderJson(report),
    ),
    await writeText(
      p.join(context.reportDir, 'report.html'),
      renderHtml(
        report,
        diff: diff,
        measurementScoreOf: (measurement) =>
            measurementScore(measurement, context.config.scoring.metrics),
      ),
    ),
  ];
  return traverse(written, (result) => result);
}

Future<Result<Baseline?, Failure>> _readBaseline(_Context context) async {
  final path = _resolve(context, context.config.baselinePath);
  if (!await fileExists(path)) {
    return const Ok(null);
  }
  return switch (await readText(path)) {
    Err(:final error) => Err(error),
    Ok(value: final text) => _decodeBaseline(path, text),
  };
}

Result<Baseline?, Failure> _decodeBaseline(String path, String text) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException catch (error) {
    return Err(
      BaselineFailure(path: path, problem: 'not valid JSON: ${error.message}'),
    );
  }
  return baselineFromJson(json).mapErr<Failure>(
    (failure) => BaselineFailure(path: path, problem: describe(failure)),
  );
}

abstract base class _FlighthouseCommand extends Command<int> {
  _FlighthouseCommand(this.environment, this.version);

  final CliEnvironment environment;

  final String version;

  Future<int> runWith(_Context context);

  @override
  Future<int> run() async =>
      switch (await _load(globalResults!, environment, version)) {
        Err(:final error) => _reportFailures([error], environment),
        Ok(value: final context) => await runWith(context),
      };
}

final class _CollectCommand extends _FlighthouseCommand {
  _CollectCommand(super.environment, super.version);

  @override
  String get name => 'collect';

  @override
  String get description =>
      'Copy each configured source\'s raw outputs into <reportDir>/raw.';

  @override
  Future<int> runWith(_Context context) async {
    if (context.config.sources.isEmpty) {
      return _reportFailures([
        const ConfigFailure(
          keyPath: 'sources',
          problem: 'no sources are configured, so there is nothing to collect',
        ),
      ], environment);
    }
    final failures = <Failure>[];
    for (final MapEntry(key: source, value: sourceConfig)
        in context.config.sources.entries) {
      final copied = await replaceJsonFiles(
        from: _resolve(context, sourceConfig.dir),
        to: _rawDir(context, source),
      );
      switch (copied) {
        case Ok(value: final paths):
          environment.out.writeln(
            'collected ${paths.length} ${source.id} '
            '${paths.length == 1 ? 'file' : 'files'}',
          );
        case Err(:final error):
          failures.add(error);
      }
    }
    return _reportFailures(failures, environment);
  }
}

final class _ReportCommand extends _FlighthouseCommand {
  _ReportCommand(super.environment, super.version);

  @override
  String get name => 'report';

  @override
  String get description =>
      'Build report.json and report.html from the collected raw outputs.';

  @override
  Future<int> runWith(_Context context) async {
    final assembled = await _assemble(context);
    final written = await _writeReport(context, assembled.report, null);
    environment.out.writeln(summaryLine(assembled.report));
    switch (written) {
      case Err(:final error):
        return _reportFailures([...assembled.failures, error], environment);
      case Ok(value: final paths):
        environment.out.writeln('wrote ${paths.join(', ')}');
        return _reportFailures(assembled.failures, environment);
    }
  }
}

final class _CiCommand extends _FlighthouseCommand {
  _CiCommand(super.environment, super.version);

  @override
  String get name => 'ci';

  @override
  String get description =>
      'Build the report and fail on new findings or score drops against '
      'the baseline.';

  @override
  Future<int> runWith(_Context context) async {
    final assembled = await _assemble(context);
    environment.out.writeln(summaryLine(assembled.report));
    if (assembled.failures.isNotEmpty) {
      await _writeReport(context, assembled.report, null);
      environment.err.writeln(
        'the gate was not evaluated because some inputs were unusable:',
      );
      return _reportFailures(assembled.failures, environment);
    }
    final baselinePath = _resolve(context, context.config.baselinePath);
    final diff = switch (await _readBaseline(context)) {
      Err(:final error) => Err<BaselineDiff, Failure>(error),
      Ok(value: null) => Err<BaselineDiff, Failure>(
        BaselineFailure(path: baselinePath, problem: 'not found'),
      ),
      Ok(value: final baseline?) => diffAgainstBaseline(
        assembled.report,
        baseline,
        baselinePath: baselinePath,
      ).mapErr<Failure>((failure) => failure),
    };
    switch (diff) {
      case Err(:final error):
        await _writeReport(context, assembled.report, null);
        return _reportFailures([error], environment);
      case Ok(value: final diff):
        final written = await _writeReport(context, assembled.report, diff);
        if (written case Err(:final error)) {
          return _reportFailures([error], environment);
        }
        final violations = evaluateGate(diff, context.config.gate);
        environment.out.writeln(
          '${diff.newFindings.length} new, ${diff.fixedFindings.length} '
          'fixed, ${diff.persistingFindings.length} unchanged',
        );
        for (final violation in violations) {
          environment.err.writeln('FAIL ${describeViolation(violation)}');
        }
        if (diff.fixedFindings.isNotEmpty) {
          environment.out.writeln(
            '${diff.fixedFindings.length} fixed; run flighthouse baseline '
            '--update to accept them',
          );
        }
        environment.out.writeln(
          violations.isEmpty ? 'gate passed' : 'gate failed',
        );
        return violations.isEmpty ? exitPassed : exitGateFailed;
    }
  }
}

final class _BaselineCommand extends _FlighthouseCommand {
  _BaselineCommand(super.environment, super.version) {
    argParser.addFlag(
      'update',
      negatable: false,
      help: 'Write the current findings and scores as the new baseline.',
    );
  }

  @override
  String get name => 'baseline';

  @override
  String get description =>
      'Show how this run differs from the baseline, or replace it with '
      '--update.';

  @override
  Future<int> runWith(_Context context) async {
    final assembled = await _assemble(context);
    if (assembled.failures.isNotEmpty) {
      environment.err.writeln(
        'the baseline was not touched because some inputs were unusable:',
      );
      return _reportFailures(assembled.failures, environment);
    }
    final baselinePath = _resolve(context, context.config.baselinePath);
    if (argResults!.flag('update')) {
      final baseline = baselineOf(assembled.report);
      final written = await writeText(
        baselinePath,
        '${const JsonEncoder.withIndent('  ').convert(baselineToJson(baseline))}\n',
      );
      switch (written) {
        case Err(:final error):
          return _reportFailures([error], environment);
        case Ok():
          environment.out.writeln(
            'wrote $baselinePath with ${baseline.findings.length} findings',
          );
          return exitPassed;
      }
    }
    switch (await _readBaseline(context)) {
      case Err(:final error):
        return _reportFailures([error], environment);
      case Ok(value: null):
        environment.out.writeln(
          'no baseline at $baselinePath yet; run flighthouse baseline --update',
        );
        return exitPassed;
      case Ok(value: final baseline?):
        switch (diffAgainstBaseline(
          assembled.report,
          baseline,
          baselinePath: baselinePath,
        )) {
          case Err(:final error):
            return _reportFailures([error], environment);
          case Ok(value: final diff):
            environment.out.writeln(
              '${diff.newFindings.length} new, ${diff.fixedFindings.length} '
              'fixed, ${diff.persistingFindings.length} unchanged',
            );
            return exitPassed;
        }
    }
  }
}

/// Runs the `flighthouse` command line and returns the process exit code.
///
/// Exit codes: 0 passed, 1 the CI gate failed, 2 a usage or configuration
/// error, 3 an unusable input or missing tool.
Future<int> runCli(
  List<String> arguments, {
  CliEnvironment? environment,
  required String version,
}) async {
  final effects = environment ?? defaultEnvironment();
  if (arguments.length == 1 && arguments.single == '--version') {
    effects.out.writeln('flighthouse $version');
    return exitPassed;
  }
  final runner =
      CommandRunner<int>(
          'flighthouse',
          'One Lighthouse-style scored report for Flutter apps, and a CI gate.',
        )
        ..argParser.addOption(
          'config',
          defaultsTo: 'flighthouse.yaml',
          help:
              'The configuration file. Relative paths in it resolve '
              'against its directory.',
        )
        ..argParser.addOption(
          'report-dir',
          help: 'Overrides reportDir from the configuration.',
        )
        ..argParser.addFlag(
          'version',
          negatable: false,
          help: 'Print the flighthouse version.',
        )
        ..addCommand(_CollectCommand(effects, version))
        ..addCommand(_ReportCommand(effects, version))
        ..addCommand(_CiCommand(effects, version))
        ..addCommand(_BaselineCommand(effects, version));
  try {
    return await runner.run(arguments) ?? exitPassed;
  } on UsageException catch (error) {
    effects.err.writeln(error);
    return exitUsageError;
  }
}
