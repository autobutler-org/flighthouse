/// Everything that can go wrong in flighthouse, as a value.
///
/// Each case carries what a user needs to act on it. [describe] renders any
/// failure as one line.
sealed class Failure {
  /// Base constructor for the failure cases.
  const Failure();

  @override
  String toString() => describe(this);
}

/// A line and column in a source file, both starting at 1.
typedef SourceLocation = ({int line, int column});

/// The configuration file is invalid.
final class ConfigFailure extends Failure {
  /// A problem with the config value at [keyPath].
  const ConfigFailure({
    required this.keyPath,
    required this.problem,
    this.location,
  });

  /// The dotted path to the offending key, such as `gate.maxScoreDrop.perf`.
  final String keyPath;

  /// What is wrong with the value.
  final String problem;

  /// Where the value sits in the config file, when known.
  final SourceLocation? location;
}

/// A JSON document does not match the expected shape.
final class SchemaFailure extends Failure {
  /// A mismatch at [jsonPath] between what was [expected] and what was [found].
  const SchemaFailure({
    required this.jsonPath,
    required this.expected,
    required this.found,
  });

  /// The path into the document, such as `$.findings[3].severity`.
  final String jsonPath;

  /// A description of the expected value.
  final String expected;

  /// A description of the value that was there.
  final String found;
}

/// A tool's output could not be turned into findings.
final class AdapterFailure extends Failure {
  /// [tool]'s output at [artifactPath] could not be read, because of [problem].
  const AdapterFailure({
    required this.tool,
    required this.artifactPath,
    required this.problem,
  });

  /// The tool whose output was read, such as `lighthouse`.
  final String tool;

  /// The file that was being read.
  final String artifactPath;

  /// What went wrong.
  final String problem;
}

/// An external tool flighthouse needs is not installed.
final class MissingToolFailure extends Failure {
  /// [tool] is missing; [installHint] says how to install it.
  const MissingToolFailure({required this.tool, required this.installHint});

  /// The missing tool, such as `Lighthouse`.
  final String tool;

  /// A command or instruction that installs it.
  final String installHint;
}

/// A file or directory operation failed.
final class IoFailure extends Failure {
  /// [operation] on [path] failed because of [reason].
  const IoFailure({
    required this.operation,
    required this.path,
    required this.reason,
  });

  /// What was being attempted, such as `read`.
  final String operation;

  /// The file or directory involved.
  final String path;

  /// The underlying error.
  final String reason;
}

/// An external process exited unsuccessfully.
final class ProcessFailure extends Failure {
  /// [command] exited with [exitCode], writing [stderr].
  const ProcessFailure({
    required this.command,
    required this.exitCode,
    required this.stderr,
  });

  /// The command line that was run.
  final String command;

  /// The process exit code.
  final int exitCode;

  /// What the process wrote to standard error.
  final String stderr;
}

/// The committed baseline cannot be compared with this run.
final class BaselineFailure extends Failure {
  /// The baseline at [path] is unusable because of [problem].
  const BaselineFailure({required this.path, required this.problem});

  /// The baseline file.
  final String path;

  /// Why it cannot be used.
  final String problem;
}

/// Renders [failure] as one line a user can act on.
String describe(Failure failure) => switch (failure) {
  ConfigFailure(:final keyPath, :final problem, location: null) =>
    'config: $keyPath: $problem',
  ConfigFailure(
    :final keyPath,
    :final problem,
    location: (:final line, :final column),
  ) =>
    'config: $keyPath (line $line, column $column): $problem',
  SchemaFailure(:final jsonPath, :final expected, :final found) =>
    '$jsonPath: expected $expected, found $found',
  AdapterFailure(:final tool, :final artifactPath, :final problem) =>
    '$tool: $artifactPath: ${firstLine(problem)}',
  MissingToolFailure(:final tool, :final installHint) =>
    '$tool not found. Install it with: $installHint',
  IoFailure(:final operation, :final path, :final reason) =>
    'could not $operation $path: ${firstLine(reason)}',
  ProcessFailure(:final command, :final exitCode, :final stderr) =>
    switch (firstLine(stderr)) {
      '' => '$command exited with code $exitCode',
      final detail => '$command exited with code $exitCode: $detail',
    },
  BaselineFailure(:final path, :final problem) =>
    'baseline $path: $problem. Run: flighthouse baseline --update',
};

/// The first non-blank line of [text], trimmed, or an empty string.
String firstLine(String text) => text
    .split('\n')
    .map((line) => line.trim())
    .firstWhere((line) => line.isNotEmpty, orElse: () => '');
