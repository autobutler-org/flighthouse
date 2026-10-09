import 'dart:io';

import 'package:flighthouse/src/config/config.dart';
import 'package:flighthouse/src/io/web_build.dart';
import 'package:flighthouse/src/result/failure.dart';
import 'package:flighthouse/src/result/result.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory project;

  setUp(() async {
    project = await Directory.systemTemp.createTemp('flighthouse-build');
  });

  tearDown(() => project.delete(recursive: true));

  final config = WebBuildConfig(
    command: const [
      'flutter',
      'build',
      'web',
      '--release',
      '--dart-define=FLIGHTHOUSE_SEMANTICS=true',
    ],
    outputDir: 'build/web',
  );

  test('passes an argv vector in the project directory', () async {
    String? executable;
    List<String>? arguments;
    String? capturedWorkingDirectory;
    final result = await buildWebApp(
      projectDir: project.path,
      config: config,
      run: (command, args, {workingDirectory}) async {
        executable = command;
        arguments = args;
        capturedWorkingDirectory = workingDirectory;
        Directory(workingDirectory!).createSync(recursive: true);
        File(p.join(workingDirectory, 'build/web/index.html'))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('app');
        return ProcessResult(1, 0, 'built', '');
      },
    );
    expect(result, isA<Ok<BuiltWebApp, Failure>>());
    expect(executable, 'flutter');
    expect(arguments, [
      'build',
      'web',
      '--release',
      '--dart-define=FLIGHTHOUSE_SEMANTICS=true',
    ]);
    expect(capturedWorkingDirectory, project.path);
    expect(
      (result as Ok<BuiltWebApp, Failure>).value.outputDir,
      p.join(project.path, 'build/web'),
    );
  });

  test('does not accept stale output after a failed build', () async {
    File(p.join(project.path, 'build/web/index.html'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('stale');
    final result = await buildWebApp(
      projectDir: project.path,
      config: config,
      run: (_, _, {workingDirectory}) async =>
          ProcessResult(1, 1, '', 'compiler failed\nmore detail'),
    );
    final failure = (result as Err<BuiltWebApp, Failure>).error;
    expect(failure, isA<ProcessFailure>());
    expect(describe(failure), contains('flutter build web'));
    expect(describe(failure), contains('compiler failed'));
  });

  test('rejects a successful command without an output directory', () async {
    final result = await buildWebApp(
      projectDir: project.path,
      config: config,
      run: (_, _, {workingDirectory}) async => ProcessResult(1, 0, '', ''),
    );
    final failure = (result as Err<BuiltWebApp, Failure>).error;
    expect(failure, isA<IoFailure>());
    expect(describe(failure), contains('build/web'));
    expect(describe(failure), contains('not found after a successful build'));
  });

  test('rejects a successful command without index.html', () async {
    Directory(p.join(project.path, 'build/web')).createSync(recursive: true);
    final result = await buildWebApp(
      projectDir: project.path,
      config: config,
      run: (_, _, {workingDirectory}) async => ProcessResult(1, 0, '', ''),
    );
    final failure = (result as Err<BuiltWebApp, Failure>).error;
    expect(failure, isA<IoFailure>());
    expect(describe(failure), contains('index.html'));
    expect(describe(failure), contains('not found after a successful build'));
  });

  test('turns a missing executable into a failure value', () async {
    final result = await buildWebApp(
      projectDir: project.path,
      config: config,
      run: (_, _, {workingDirectory}) async => throw const ProcessException(
        'flutter',
        ['build', 'web'],
        'No such file',
      ),
    );
    final failure = (result as Err<BuiltWebApp, Failure>).error;
    expect(failure, isA<IoFailure>());
    expect(describe(failure), contains('flutter'));
    expect(describe(failure), contains('No such file'));
  });
}
