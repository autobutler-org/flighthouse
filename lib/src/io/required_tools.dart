import 'dart:io';

import '../result/failure.dart';
import '../result/result.dart';
import 'web_build.dart';

const missingLighthouse = MissingToolFailure(
  tool: 'Lighthouse',
  installHint: 'npm install -g lighthouse',
);

const _flutterInstallHint =
    'follow https://docs.flutter.dev/get-started/install and put flutter on '
    'PATH';

final _versionPattern = RegExp(r'^v?\d+\.\d+\.\d+');

MissingToolFailure missingBuildTool(String executable) => _isFlutter(executable)
    ? const MissingToolFailure(
        tool: 'Flutter',
        installHint: _flutterInstallHint,
      )
    : MissingToolFailure(
        tool: executable,
        installHint:
            'install it or change web.build.command to a command that is '
            'installed',
      );

bool _isFlutter(String executable) {
  final name = executable.split(RegExp(r'[\\/]')).last.toLowerCase();
  return name == 'flutter' || name == 'flutter.bat';
}

Future<Result<String, Failure>> checkLighthouse({
  required List<String> command,
  required ProcessRun run,
}) async {
  final arguments = [...command.skip(1), '--version'];
  final commandText = [command.first, ...arguments].join(' ');
  final ProcessResult result;
  try {
    result = await run(command.first, arguments);
  } on ProcessException {
    return const Err(missingLighthouse);
  }
  if (result.exitCode != 0) {
    return Err(
      ProcessFailure(
        command: commandText,
        exitCode: result.exitCode,
        stderr: '${result.stderr}',
      ),
    );
  }
  final version = firstLine('${result.stdout}');
  if (!_versionPattern.hasMatch(version)) {
    return Err(
      IoFailure(
        operation: 'read the Lighthouse version from',
        path: commandText,
        reason:
            'printed ${version.isEmpty ? 'no version' : 'an unusable version'}'
            '; reinstall it with: ${missingLighthouse.installHint}',
      ),
    );
  }
  return Ok(version);
}

String chromeAcquireHint(String detail) {
  final lower = detail.toLowerCase();
  if (lower.contains('unzip')) {
    return 'unzip is required to unpack Chrome; install it, for example: '
        'apt install unzip';
  }
  if (lower.contains('error while loading shared libraries')) {
    return 'Chrome is missing system libraries; install them, for example: '
        'apt install libnss3 libatk-bridge2.0-0 libgbm1 libasound2';
  }
  return detail;
}
