import 'dart:io';

import 'package:flighthouse/flighthouse.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('packageVersion matches the pubspec version', () {
    final pubspec =
        loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    expect(packageVersion, pubspec['version']);
  });

  test('the changelog has an entry for this version', () {
    expect(
      File('CHANGELOG.md').readAsLinesSync(),
      contains('## $packageVersion'),
    );
  });
}
