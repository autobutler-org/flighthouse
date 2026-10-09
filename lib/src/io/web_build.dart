import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/config.dart';
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
