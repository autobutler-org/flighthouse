import 'dart:io';

import 'package:flighthouse/src/io/git.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('flighthouse-git');
  });

  tearDown(() => root.delete(recursive: true));

  Future<String> git(List<String> arguments) async {
    final result = await Process.run('git', [
      '-c',
      'user.name=flighthouse',
      '-c',
      'user.email=flighthouse@example.com',
      '-c',
      'commit.gpgsign=false',
      ...arguments,
    ], workingDirectory: root.path);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return '${result.stdout}'.trim();
  }

  test('reads the short commit of HEAD', () async {
    await git(['init', '--quiet']);
    await git(['commit', '--quiet', '--allow-empty', '-m', 'first']);
    final head = await git(['rev-parse', '--short', 'HEAD']);
    expect(await currentCommit(root.path), head);
  });

  test('is null in a repository without commits', () async {
    await git(['init', '--quiet']);
    expect(await currentCommit(root.path), isNull);
  });

  test('is null outside a repository', () async {
    final outside = await Directory.systemTemp.createTemp('flighthouse-nogit');
    addTearDown(() => outside.delete(recursive: true));
    final result = await Process.run('git', [
      'rev-parse',
      '--git-dir',
    ], workingDirectory: outside.path);
    if (result.exitCode == 0) {
      markTestSkipped('the temp directory is inside a git repository');
      return;
    }
    expect(await currentCommit(outside.path), isNull);
  });

  test('is null when the directory does not exist', () async {
    expect(await currentCommit('${root.path}/missing'), isNull);
  });
}
