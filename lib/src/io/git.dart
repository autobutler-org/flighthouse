import 'dart:io';

Future<String?> currentCommit(String directory) async {
  try {
    final result = await Process.run('git', [
      'rev-parse',
      '--short',
      'HEAD',
    ], workingDirectory: directory);
    final commit = '${result.stdout}'.trim();
    return result.exitCode == 0 && commit.isNotEmpty ? commit : null;
  } on ProcessException {
    return null;
  }
}
