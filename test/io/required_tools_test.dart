import 'dart:io';

import 'package:flighthouse/src/io/required_tools.dart';
import 'package:flighthouse/src/result/failure.dart';
import 'package:flighthouse/src/result/result.dart';
import 'package:test/test.dart';

Future<Result<String, Failure>> _check(
  Future<ProcessResult> Function(String, List<String>) run, [
  List<String> command = const ['lighthouse'],
]) => checkLighthouse(
  command: command,
  run: (executable, arguments, {workingDirectory}) =>
      run(executable, arguments),
);

Failure _failure(Result<String, Failure> result) =>
    (result as Err<String, Failure>).error;

void main() {
  test('a usable version passes and is returned', () async {
    final result = await _check(
      (_, _) async => ProcessResult(1, 0, '12.3.0\n', ''),
    );
    expect((result as Ok<String, Failure>).value, '12.3.0');
  });

  test('the version check appends --version to the whole command', () async {
    late List<String> seen;
    await _check((executable, arguments) async {
      seen = [executable, ...arguments];
      return ProcessResult(1, 0, '12.3.0', '');
    }, const ['npx', 'lighthouse']);
    expect(seen, ['npx', 'lighthouse', '--version']);
  });

  test('a missing executable names Lighthouse and how to install it', () async {
    final failure = _failure(
      await _check(
        (_, _) async => throw const ProcessException('lighthouse', [], 'no'),
      ),
    );
    expect(failure, isA<MissingToolFailure>());
    expect(
      describe(failure),
      'Lighthouse not found. Install it with: npm install -g lighthouse',
    );
  });

  test('an installed executable that exits non-zero is a failure', () async {
    final failure = _failure(
      await _check(
        (_, _) async => ProcessResult(1, 127, '', 'node: not found'),
      ),
    );
    expect(failure, isA<ProcessFailure>());
    expect(describe(failure), contains('exited with code 127'));
    expect(describe(failure), contains('node: not found'));
  });

  for (final output in ['', 'not a version\n', '{"lighthouseVersion":"1"}']) {
    test('output "$output" is an unusable version', () async {
      final failure = _failure(
        await _check((_, _) async => ProcessResult(1, 0, output, '')),
      );
      expect(failure, isA<IoFailure>());
      expect(describe(failure), contains('npm install -g lighthouse'));
    });
  }

  test('a missing flutter build names Flutter and how to install it', () {
    final failure = missingBuildTool('/opt/flutter/bin/flutter');
    expect(describe(failure), contains('Flutter not found'));
    expect(describe(failure), contains('docs.flutter.dev'));
  });

  test('a missing custom build command names that command', () {
    final failure = missingBuildTool('make');
    expect(describe(failure), contains('make not found'));
    expect(describe(failure), contains('web.build.command'));
  });

  test('Chrome acquisition hints name unzip and shared libraries', () {
    expect(
      chromeAcquireHint('ProcessException: unzip: No such file'),
      contains('apt install unzip'),
    );
    expect(
      chromeAcquireHint('error while loading shared libraries: libnss3.so'),
      contains('libnss3'),
    );
    expect(chromeAcquireHint('boom'), 'boom');
  });
}
