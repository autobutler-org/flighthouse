import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../pipeline/flutter_pin.dart';
import '../result/failure.dart';
import '../result/result.dart';
import 'required_tools.dart';

typedef ProcessRun = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
});

final class BuiltWebApp {
  const BuiltWebApp({required this.projectDir, required this.outputDir});

  final String projectDir;
  final String outputDir;
}

Future<ProcessResult> _runProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) => Process.run(executable, arguments, workingDirectory: workingDirectory);

String _commandText(List<String> command) => command.join(' ');

Future<Result<BuiltWebApp, Failure>> buildWebApp({
  required String projectDir,
  required WebBuildConfig config,
  ProcessRun run = _runProcess,
}) async {
  final command = config.command;
  final pin = await _checkFlutterPin(
    projectDir: projectDir,
    flutter: _isFlutter(command.first) ? command.first : 'flutter',
    run: run,
  );
  if (pin case Err(:final error)) {
    return Err(error);
  }
  final result = await _runBuild(command, projectDir: projectDir, run: run);
  switch (result) {
    case Err(:final error):
      return Err(error);
    case Ok(value: final process) when process.exitCode != 0:
      return Err(
        ProcessFailure(
          command: _commandText(command),
          exitCode: process.exitCode,
          stderr: '${process.stderr}',
        ),
      );
    case Ok():
      final outputDir = p.normalize(p.join(projectDir, config.outputDir));
      final indexPath = p.join(outputDir, 'index.html');
      try {
        if (!await Directory(outputDir).exists()) {
          return Err(
            IoFailure(
              operation: 'use web build output',
              path: outputDir,
              reason: 'not found after a successful build',
            ),
          );
        }
        if (!await File(indexPath).exists()) {
          return Err(
            IoFailure(
              operation: 'use web entrypoint',
              path: indexPath,
              reason: 'not found after a successful build',
            ),
          );
        }
        return Ok(BuiltWebApp(projectDir: projectDir, outputDir: outputDir));
      } on FileSystemException catch (error) {
        return Err(
          IoFailure(
            operation: 'inspect web build output',
            path: outputDir,
            reason: error.osError?.message ?? error.message,
          ),
        );
      }
  }
}

Future<Result<ProcessResult, Failure>> _runBuild(
  List<String> command, {
  required String projectDir,
  required ProcessRun run,
}) async {
  try {
    return Ok(
      await run(
        command.first,
        command.sublist(1),
        workingDirectory: projectDir,
      ),
    );
  } on ProcessException {
    return Err(missingBuildTool(command.first));
  }
}

bool _isFlutter(String executable) =>
    p.basenameWithoutExtension(executable).toLowerCase() == 'flutter';

Future<Result<void, Failure>> _checkFlutterPin({
  required String projectDir,
  required String flutter,
  required ProcessRun run,
}) async {
  final pubspecPath = p.join(projectDir, 'pubspec.yaml');
  final String pubspecText;
  try {
    final pubspec = File(pubspecPath);
    if (!await pubspec.exists()) {
      return const Ok(null);
    }
    pubspecText = await pubspec.readAsString();
  } on FileSystemException catch (error) {
    return Err(
      IoFailure(
        operation: 'read',
        path: pubspecPath,
        reason: error.osError?.message ?? error.message,
      ),
    );
  }
  switch (readFlutterPin(pubspecText, pubspecPath: pubspecPath)) {
    case Err(:final error):
      return Err(error);
    case Ok(value: null):
      return const Ok(null);
    case Ok(value: final String pinned):
      final found = await _flutterVersion(
        flutter: flutter,
        projectDir: projectDir,
        run: run,
      );
      return found.flatMap(
        (found) => checkFlutterPin(
          pinned: pinned,
          found: found,
          pubspecPath: pubspecPath,
        ),
      );
  }
}

Future<Result<String, Failure>> _flutterVersion({
  required String flutter,
  required String projectDir,
  required ProcessRun run,
}) async {
  const arguments = ['--version', '--machine'];
  final command = _commandText([flutter, ...arguments]);
  final ProcessResult result;
  try {
    result = await run(flutter, arguments, workingDirectory: projectDir);
  } on ProcessException {
    return Err(missingBuildTool(flutter));
  }
  if (result.exitCode != 0) {
    return Err(
      ProcessFailure(
        command: command,
        exitCode: result.exitCode,
        stderr: '${result.stderr}',
      ),
    );
  }
  return readFlutterVersion('${result.stdout}', command: command);
}
