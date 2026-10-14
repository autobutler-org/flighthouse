import 'dart:io';

import 'package:flighthouse/src/pipeline/flutter_pin.dart';
import 'package:flighthouse/src/result/failure.dart';
import 'package:flighthouse/src/result/result.dart';
import 'package:test/test.dart';

const _command = 'flutter --version --machine';

String _recordedOutput() =>
    File('test/fixtures/flutter_pin/3.47.7/version_machine.json')
        .readAsStringSync();

void main() {
  group('readFlutterPin', () {
    test('reads an exact environment.flutter version', () {
      const pubspec = '''
name: quark
environment:
  sdk: ^3.11.0
  flutter: 3.47.7
''';
      expect(
        readFlutterPin(pubspec, pubspecPath: 'pubspec.yaml'),
        const Ok<String?, Failure>('3.47.7'),
      );
    });

    test('reads a quoted pin', () {
      const pubspec = "environment:\n  flutter: '3.47.7'\n";
      expect(
        readFlutterPin(pubspec, pubspecPath: 'pubspec.yaml'),
        const Ok<String?, Failure>('3.47.7'),
      );
    });

    for (final (name, pubspec) in [
      ('no environment', 'name: app\n'),
      ('no flutter key', 'environment:\n  sdk: ^3.11.0\n'),
      ('a range', "environment:\n  flutter: '>=3.40.0'\n"),
      ('a caret constraint', 'environment:\n  flutter: ^3.47.7\n'),
      ('an empty document', ''),
    ]) {
      test('declares no pin with $name', () {
        expect(
          readFlutterPin(pubspec, pubspecPath: 'pubspec.yaml'),
          const Ok<String?, Failure>(null),
        );
      });
    }

    test('names the pubspec when it is not YAML', () {
      final result = readFlutterPin(
        'environment: [',
        pubspecPath: '/app/pubspec.yaml',
      );
      final failure = (result as Err<String?, Failure>).error;
      expect(failure, isA<IoFailure>());
      expect(describe(failure), contains('/app/pubspec.yaml'));
    });
  });

  group('readFlutterVersion', () {
    test('reads frameworkVersion from recorded output', () {
      expect(
        readFlutterVersion(_recordedOutput(), command: _command),
        const Ok<String, Failure>('3.47.7'),
      );
    });

    test('skips a banner printed before the JSON', () {
      expect(
        readFlutterVersion(
          'Downloading Dart SDK...\n${_recordedOutput()}',
          command: _command,
        ),
        const Ok<String, Failure>('3.47.7'),
      );
    });

    for (final (name, output) in [
      ('empty output', ''),
      ('plain text', 'Flutter 3.47.7 • channel stable'),
      ('malformed JSON', '{"frameworkVersion": '),
      ('no frameworkVersion', '{"channel": "stable"}'),
      ('a non-version value', '{"frameworkVersion": "unknown"}'),
    ]) {
      test('rejects $name', () {
        final result = readFlutterVersion(output, command: _command);
        final failure = (result as Err<String, Failure>).error;
        expect(failure, isA<IoFailure>());
        expect(describe(failure), contains(_command));
        expect(describe(failure), contains('frameworkVersion'));
      });
    }
  });

  group('checkFlutterPin', () {
    test('accepts the pinned version', () {
      expect(
        checkFlutterPin(
          pinned: '3.47.7',
          found: '3.47.7',
          pubspecPath: 'pubspec.yaml',
        ),
        isA<Ok<void, Failure>>(),
      );
    });

    test('names both versions and the fix on a mismatch', () {
      final result = checkFlutterPin(
        pinned: '3.47.7',
        found: '3.47.6',
        pubspecPath: '/quark/pubspec.yaml',
      );
      final message = describe((result as Err<void, Failure>).error);
      expect(message, contains('Flutter 3.47.7'));
      expect(message, contains('/quark/pubspec.yaml'));
      expect(message, contains('flutter on PATH is 3.47.6'));
      expect(message, contains('first on PATH'));
    });
  });
}
