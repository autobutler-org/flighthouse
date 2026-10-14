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

  test('a failed build reports the last lines of its stderr', () async {
    final result = await buildWebApp(
      projectDir: project.path,
      config: config,
      run: (_, _, {workingDirectory}) async => ProcessResult(
        1,
        1,
        '',
        'Resolving dependencies...\n'
            'The current Flutter SDK version is 3.47.6.\n\n'
            'Because quark requires Flutter SDK version 3.47.7, version '
            'solving failed.\n',
      ),
    );
    final failure = (result as Err<BuiltWebApp, Failure>).error;
    expect(
      describe(failure),
      contains(
        'Because quark requires Flutter SDK version 3.47.7, version solving '
        'failed.',
      ),
    );
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
    expect(failure, isA<MissingToolFailure>());
    expect(describe(failure), contains('Flutter not found'));
    expect(describe(failure), contains('docs.flutter.dev'));
  });

  group('Flutter pin', () {
    final machineOutput = File(
      'test/fixtures/flutter_pin/3.47.7/version_machine.json',
    ).readAsStringSync();

    void pin(String version) => File(p.join(project.path, 'pubspec.yaml'))
        .writeAsStringSync(
          'name: quark\nenvironment:\n  sdk: ^3.11.0\n  flutter: $version\n',
        );

    Future<Result<BuiltWebApp, Failure>> build(
      List<List<String>> calls, {
      String versionOutput = '',
      int versionExitCode = 0,
    }) => buildWebApp(
      projectDir: project.path,
      config: config,
      run: (command, args, {workingDirectory}) async {
        calls.add([command, ...args]);
        if (args.contains('--machine')) {
          return ProcessResult(1, versionExitCode, versionOutput, 'boom');
        }
        File(p.join(workingDirectory!, 'build/web/index.html'))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('app');
        return ProcessResult(1, 0, '', '');
      },
    );

    test('builds when the Flutter on PATH matches the pin', () async {
      pin('3.47.7');
      final calls = <List<String>>[];
      final result = await build(calls, versionOutput: machineOutput);
      expect(result, isA<Ok<BuiltWebApp, Failure>>());
      expect(calls.first, ['flutter', '--version', '--machine']);
      expect(calls, hasLength(2));
    });

    test('fails before building on a mismatch', () async {
      pin('3.47.8');
      final calls = <List<String>>[];
      final result = await build(calls, versionOutput: machineOutput);
      final failure = (result as Err<BuiltWebApp, Failure>).error;
      expect(failure, isA<MissingToolFailure>());
      final message = describe(failure);
      expect(message, contains('Flutter 3.47.8'));
      expect(message, contains('flutter on PATH is 3.47.7'));
      expect(message, contains(p.join(project.path, 'pubspec.yaml')));
      expect(message, contains('first on PATH'));
      expect(calls, [
        ['flutter', '--version', '--machine'],
      ]);
    });

    test('does not ask Flutter for its version without a pin', () async {
      File(p.join(project.path, 'pubspec.yaml'))
          .writeAsStringSync('name: app\nenvironment:\n  sdk: ^3.11.0\n');
      final calls = <List<String>>[];
      final result = await build(calls);
      expect(result, isA<Ok<BuiltWebApp, Failure>>());
      expect(calls.single.first, 'flutter');
      expect(calls.single, isNot(contains('--machine')));
    });

    test('fails before building on unparsable version output', () async {
      pin('3.47.7');
      final calls = <List<String>>[];
      final result = await build(calls, versionOutput: 'Flutter 3.47.7');
      final failure = (result as Err<BuiltWebApp, Failure>).error;
      expect(failure, isA<IoFailure>());
      expect(describe(failure), contains('flutter --version --machine'));
      expect(calls, hasLength(1));
    });

    test('reports a failed version command', () async {
      pin('3.47.7');
      final result = await build([], versionExitCode: 1);
      final failure = (result as Err<BuiltWebApp, Failure>).error;
      expect(failure, isA<ProcessFailure>());
      expect(describe(failure), contains('flutter --version --machine'));
    });

    test('reports a missing Flutter when a pin is declared', () async {
      pin('3.47.7');
      final result = await buildWebApp(
        projectDir: project.path,
        config: WebBuildConfig(
          command: const ['make', 'build/frontend/web'],
          outputDir: 'build/web',
        ),
        run: (command, _, {workingDirectory}) async =>
            throw ProcessException(command, const [], 'No such file'),
      );
      final failure = (result as Err<BuiltWebApp, Failure>).error;
      expect(describe(failure), contains('Flutter not found'));
    });

    test('asks the build command\'s own Flutter for its version', () async {
      pin('3.47.7');
      String? executable;
      await buildWebApp(
        projectDir: project.path,
        config: WebBuildConfig(
          command: const ['/opt/flutter/bin/flutter', 'build', 'web'],
          outputDir: 'build/web',
        ),
        run: (command, args, {workingDirectory}) async {
          executable ??= command;
          return ProcessResult(1, 0, machineOutput, '');
        },
      );
      expect(executable, '/opt/flutter/bin/flutter');
    });
  });
}
