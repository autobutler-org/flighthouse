import 'dart:convert';

import 'package:yaml/yaml.dart';

import '../result/failure.dart';
import '../result/result.dart';

final _exactVersion = RegExp(r'^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.+-]+)?$');

Result<String?, Failure> readFlutterPin(
  String pubspecText, {
  required String pubspecPath,
}) {
  final Object? root;
  try {
    root = loadYaml(pubspecText);
  } on YamlException catch (exception) {
    return Err(
      IoFailure(
        operation: 'read the Flutter pin from',
        path: pubspecPath,
        reason: exception.message,
      ),
    );
  }
  return switch (root) {
    {'environment': {'flutter': final String constraint}}
        when _exactVersion.hasMatch(constraint.trim()) =>
      Ok(constraint.trim()),
    _ => const Ok(null),
  };
}

Result<String, Failure> readFlutterVersion(
  String machineOutput, {
  required String command,
}) {
  final start = machineOutput.indexOf('{');
  final end = machineOutput.lastIndexOf('}');
  final Object? decoded;
  try {
    decoded = start < 0 || end < start
        ? null
        : jsonDecode(machineOutput.substring(start, end + 1));
  } on FormatException {
    return Err(_unreadableVersion(command));
  }
  return switch (decoded) {
    {'frameworkVersion': final String version}
        when _exactVersion.hasMatch(version) =>
      Ok(version),
    _ => Err(_unreadableVersion(command)),
  };
}

IoFailure _unreadableVersion(String command) => IoFailure(
  operation: 'read the Flutter version from',
  path: command,
  reason:
      'printed no frameworkVersion; reinstall Flutter from '
      'https://docs.flutter.dev/get-started/install',
);

Result<void, Failure> checkFlutterPin({
  required String pinned,
  required String found,
  required String pubspecPath,
}) => pinned == found
    ? const Ok(null)
    : Err(
        MissingToolFailure(
          tool:
              'Flutter $pinned (pinned by $pubspecPath; flutter on PATH is '
              '$found)',
          installHint:
              'follow https://docs.flutter.dev/install/archive to get Flutter '
              '$pinned and put its bin directory first on PATH',
        ),
      );
