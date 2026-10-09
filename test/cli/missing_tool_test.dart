import 'dart:io';

import 'package:flighthouse/src/cli/cli.dart';
import 'package:flighthouse/src/io/browser.dart';
import 'package:flighthouse/src/result/result.dart';
import 'package:test/test.dart';

import 'web_lighthouse_test.dart' show RecordingBrowser, Run, Workspace;

const _config = 'app: quark\nweb:\n  routes: [/files]\n';

void main() {
  late Directory root;
  late Workspace workspace;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('flighthouse-missing-tool');
    workspace = Workspace(root)..write('flighthouse.yaml', _config);
  });

  tearDown(() => root.delete(recursive: true));

  Future<({Run run, List<String> calls, int launches})> collectWith(
    Future<ProcessResult> Function(String, List<String>) respond,
  ) async {
    final calls = <String>[];
    var launches = 0;
    final browser = RecordingBrowser();
    final run = await workspace.execute(
      ['collect'],
      runProcess: (executable, arguments, {workingDirectory}) {
        calls.add([executable, ...arguments].join(' '));
        return respond(executable, arguments);
      },
      launchBrowser: (_) async {
        launches++;
        return Ok(browser.session);
      },
    );
    return (run: run, calls: calls, launches: launches);
  }

  void expectNothingStored() {
    expect(workspace.exists('flighthouse-baseline.json'), isFalse);
    expect(
      Directory(workspace.path('.flighthouse/raw/lighthouse')).existsSync(),
      isFalse,
    );
    expect(
      Directory(workspace.path('.flighthouse/raw/axe')).existsSync(),
      isFalse,
    );
    expect(workspace.exists('.flighthouse/report.json'), isFalse);
  }

  test('a missing lighthouse stops collect before the build', () async {
    final outcome = await collectWith(
      (executable, _) async =>
          throw ProcessException(executable, const [], 'No such file'),
    );

    expect(outcome.run.code, exitInputError);
    expect(
      outcome.run.err,
      contains(
        'Lighthouse not found. Install it with: npm install -g lighthouse',
      ),
    );
    expect(outcome.calls, ['lighthouse --version']);
    expect(outcome.launches, 0);
    expectNothingStored();
  });

  test('a lighthouse that fails its version check stops collect', () async {
    final outcome = await collectWith(
      (_, _) async => ProcessResult(1, 1, '', 'node: command not found'),
    );

    expect(outcome.run.code, exitInputError);
    expect(
      outcome.run.err,
      contains('lighthouse --version exited with code 1'),
    );
    expect(outcome.run.err, contains('node: command not found'));
    expect(outcome.calls, ['lighthouse --version']);
    expect(outcome.launches, 0);
    expectNothingStored();
  });

  test('a lighthouse that prints an unusable version stops collect', () async {
    final outcome = await collectWith(
      (_, _) async => ProcessResult(1, 0, 'Segmentation fault\n', ''),
    );

    expect(outcome.run.code, exitInputError);
    expect(outcome.run.err, contains('unusable version'));
    expect(outcome.run.err, contains('npm install -g lighthouse'));
    expect(outcome.calls, ['lighthouse --version']);
    expect(outcome.launches, 0);
    expectNothingStored();
  });

  test('a missing flutter is a missing tool, not a clean audit', () async {
    final outcome = await collectWith((executable, _) async {
      if (executable == 'flutter') {
        throw ProcessException(executable, const [], 'No such file');
      }
      return ProcessResult(1, 0, '12.0.0\n', '');
    });

    expect(outcome.run.code, exitInputError);
    expect(outcome.run.err, contains('Flutter not found. Install it with:'));
    expect(outcome.run.err, contains('docs.flutter.dev'));
    expect(outcome.launches, 0);
    expectNothingStored();
  });

  test('a failed flutter build is a failure, not a clean audit', () async {
    final outcome = await collectWith((executable, _) async {
      if (executable == 'flutter') {
        return ProcessResult(1, 1, '', 'build failed');
      }
      return ProcessResult(1, 0, '12.0.0\n', '');
    });

    expect(outcome.run.code, exitInputError);
    expect(outcome.run.err, contains('build failed'));
    expect(outcome.launches, 0);
    expectNothingStored();
  });

  test('report, ci, and baseline never probe a web tool', () async {
    for (final arguments in [
      ['report'],
      ['ci'],
      ['baseline'],
      ['baseline', '--update'],
    ]) {
      final probes = <String>[];
      var launches = 0;
      await workspace.execute(
        arguments,
        runProcess: (executable, processArguments, {workingDirectory}) async {
          probes.add([executable, ...processArguments].join(' '));
          return ProcessResult(1, 0, '12.0.0\n', '');
        },
        launchBrowser: (BrowserViewport _) async {
          launches++;
          return Ok(RecordingBrowser().session);
        },
      );
      expect(probes, isEmpty, reason: arguments.join(' '));
      expect(launches, 0, reason: arguments.join(' '));
    }
    expect(workspace.exists('flighthouse-baseline.json'), isFalse);
  });
}
