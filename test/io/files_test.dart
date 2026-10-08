import 'dart:io';

import 'package:flighthouse/src/io/files.dart';
import 'package:flighthouse/src/result/failure.dart';
import 'package:flighthouse/src/result/result.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('flighthouse-files');
  });
  tearDown(() => root.delete(recursive: true));

  File sourceAt(String relative) => File(p.join(root.path, relative))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('{"recorded":true}');

  test(
    'collect keeps raw inputs already in the collection directory',
    () async {
      final source = sourceAt('raw/lighthouse/report.json');
      final result = await replaceJsonFiles(
        from: source.parent.path,
        to: source.parent.path,
      );
      expect(result, isA<Ok<List<String>, IoFailure>>());
      expect(source.readAsStringSync(), '{"recorded":true}');
      switch (result) {
        case Ok(value: final paths):
          expect(paths, [source.path]);
          expect(() => paths.add('unexpected.json'), throwsUnsupportedError);
        case Err(:final error):
          fail('$error');
      }
    },
  );

  test('collect recognizes a symbolic link to its source directory', () async {
    final source = sourceAt('input/report.json');
    final alias = Link(p.join(root.path, 'alias'));
    await alias.create(source.parent.path);
    final result = await replaceJsonFiles(
      from: source.parent.path,
      to: alias.path,
    );
    expect(result, isA<Ok<List<String>, IoFailure>>());
    expect(source.readAsStringSync(), '{"recorded":true}');
    expect(await alias.exists(), isTrue);
  });

  test(
    'collect creates a missing destination under an aliased parent',
    () async {
      final source = sourceAt('input/report.json');
      final destination = Directory(p.join(root.path, 'output'));
      await destination.create();
      final alias = Link(p.join(root.path, 'alias'));
      await alias.create(destination.path);
      final to = p.join(alias.path, 'new', 'raw');
      final result = await replaceJsonFiles(from: source.parent.path, to: to);
      expect(result, isA<Ok<List<String>, IoFailure>>());
      expect(
        File(p.join(destination.path, 'new', 'raw', 'report.json'))
            .readAsStringSync(),
        source.readAsStringSync(),
      );
      expect(await alias.exists(), isTrue);
    },
  );

  test(
    'collect replaces a sibling whose name starts with the source name',
    () async {
      final source = sourceAt('input/report.json');
      final previous = sourceAt('input-copy/stale.json');
      final result = await replaceJsonFiles(
        from: source.parent.path,
        to: previous.parent.path,
      );
      expect(result, isA<Ok<List<String>, IoFailure>>());
      expect(source.readAsStringSync(), '{"recorded":true}');
      expect(previous.existsSync(), isFalse);
      expect(
        File(p.join(previous.parent.path, 'report.json')).readAsStringSync(),
        source.readAsStringSync(),
      );
    },
  );

  test('collect reports an unavailable filesystem root', () async {
    final source = sourceAt('input/report.json');
    final roots = await Future.wait([
      for (final letter in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split(''))
        Directory('$letter:\\')
            .exists()
            .then((exists) => (path: '$letter:\\', exists: exists)),
    ]);
    final unavailable = roots.firstWhere((candidate) => !candidate.exists);
    final result = await replaceJsonFiles(
      from: source.parent.path,
      to: p.join(unavailable.path, 'raw'),
    ).timeout(const Duration(seconds: 2));
    expect(result, isA<Err<List<String>, IoFailure>>());
    switch (result) {
      case Err(:final error):
        expect(error.operation, 'copy into');
        expect(error.path, p.join(unavailable.path, 'raw'));
        expect(error.reason, isNotEmpty);
      case Ok():
        fail('an unavailable drive must return an IO failure');
    }
    expect(source.readAsStringSync(), '{"recorded":true}');
  }, testOn: 'windows');

  for (final aliased in [false, true]) {
    test(
      'collect rejects a destination containing its source ($aliased)',
      () async {
        final source = sourceAt('raw/lighthouse/session/report.json');
        final destination = source.parent.parent;
        final unrelated = sourceAt('raw/lighthouse/other.txt');
        final alias = Link(p.join(root.path, 'alias'));
        if (aliased) await alias.create(destination.path);
        final result = await replaceJsonFiles(
          from: source.parent.path,
          to: aliased ? alias.path : destination.path,
        );
        expect(result, isA<Err<List<String>, IoFailure>>());
        expect(source.readAsStringSync(), '{"recorded":true}');
        expect(unrelated.existsSync(), isTrue);
        switch (result) {
          case Err(:final error):
            expect(error.reason, contains('contains the source directory'));
          case Ok():
            fail('an overlapping collection must fail before deleting inputs');
        }
      },
    );
  }
}
